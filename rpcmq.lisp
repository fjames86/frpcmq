;;;; Copyright (c) Frank James 2015 <frank.a.james@gmail.com>
;;;; This code is licensed under the MIT license.

;; 
;; On the server:
;; (defparameter *q* (create-queue "myname"))
;; (dotimes (i 10)
;;   (multiple-value-bind (data id) (receive *q*)
;;     (format t "~D ~S~%" id data)))
;;      
;; On the client:
;; (let ((handle (call-open "myname")))
;;   (call-post handle #(1 2 3 4))
;;   (call-post handle #(4 3 2 1)))
;;
;; The output on the server is then
;; 1 #(1 2 3 4)
;; 2 #(4 3 2 1)
;; 
;;

(defpackage #:frpcmq 
  (:use #:cl #:frpc)
  (:export #:call-null
           #:call-post
           #:call-dump

           ;; server
           #:get-message
           #:create-queue
           #:delete-queue
           
           ;; client
           #:open-queue
           #:close-queue
           #:post-message
           #:discover-queues))

(in-package #:frpcmq)

;; a random program number I generated
(defprogram rpcmq #x2666385D)

;; ------------------------------

(defun handle-null (arg)
  (declare (ignore arg))
  nil)

(defrpc call-null 0 :void :void
  (:program rpcmq 1)
  (:handler #'handle-null))

;; ----------------------------

;; PG's queue system
(defun make-queue () (cons nil nil))

(defun enqueue (o q)
  (if (null (car q))
      (setf (cdr q) (setf (car q) (list o)))
      (setf (cdr (cdr q)) (list o)
            (cdr q) (cdr (cdr q))))
  (car q))

(defun dequeue (q)
  (let ((val (pop (car q))))
    (when (null (car q))
      (setf (cdr q) nil))
    val))

;; -------------------------------

(defstruct message 
  id data)

(defstruct mq 
  handle seqno
  messages 
  lock condv)

(defvar *mqlist* nil
  "List of message queues.")

(defun find-queue (handle)
  (find handle *mqlist*
	:key #'mq-handle
	:test #'=))

(defun create-queue (handle)
  "Create a new message queue.

HANDLE ::= integer to identify the queue.

Returns the queue."
  (declare (type integer handle))
  (let ((q (find-queue handle)))
    (when q 
      (return-from create-queue q)))
  (let ((q (make-mq :handle handle
                    :seqno 0
                    :lock (bt:make-lock)
                    :condv (bt:make-condition-variable)
                    :messages (make-queue))))
    (push q *mqlist*)
    q))

(defun delete-queue (q)
  "Delete the queue."
  (declare (type mq q))
  (setf *mqlist* (remove q *mqlist*)))

(defun get-message (queue &optional return-immediately timeout)
  "Receive a message from the queue. 
QUEUE ::= a message queue returned from a previous call to CREATE-QUEUE.

RETURN-IMMEDIATELY ::= if true, will return immediately with the first available message, 
no messages available returns immediately with value nil. If false will block until a message arrives.

TIMEOUT ::= if supplied, should be the time to wait in seconds for a message. If the timeout expires returns nil.

Returns (values data id)."
  (declare (type mq queue))
  (bt:with-lock-held ((mq-lock queue))
    (let ((m (dequeue (mq-messages queue))))
      (cond
        (m
         (values (message-data m) (message-id m)))
        (return-immediately 
         ;; we don't want to block, return immediately 
         nil)
        (t 
         ;; block until the condition varaible is signalled
         (if timeout
	     (handler-case (bt:with-timeout (timeout) (bt:condition-wait (mq-condv queue) (mq-lock queue)))
	       (bt:timeout () (return-from get-message nil)))
	     (bt:condition-wait (mq-condv queue) (mq-lock queue)))
         (let ((m (dequeue (mq-messages queue))))
           (values (message-data m) (message-id m))))))))

;; ------------------------------------

(defun handle-post (arg)
  (destructuring-bind (handle id data) arg
    (let ((q (find-queue handle)))
      (when q 
	(bt:with-lock-held ((mq-lock q))
	  (incf (mq-seqno q))
	  (enqueue (make-message :id id :data data)
		   (mq-messages q)))
	;; signal the condition variable 
	(bt:condition-notify (mq-condv q))))
    (error "Be silent")))

(defrpc call-post 1
  (:list :uint32 :uint32 (:varray* :octet)) ;; handle id data
  :void
  (:arg-transformer (handle id data) 
    (list handle id data))
  (:program rpcmq 1)
  (:handler #'handle-post)
  (:documentation "Post a message to the remote message queue."))

(defstruct client-queue 
  conn handle id)

(defun open-queue (host handle)
  "Open a remote queue. Returns a queue object to be used to send messages. This must be closed with a call to CLOSE-QUEUE.

HOST ::= name of the host that exports the queue.
HANDLE ::= an integer specifying the queue name.

Returns a queue object."
  (declare (type integer handle))
  (let ((port (frpc.bind:call-get-port (program-id 'rpcmq) 1 
				       :host host)))
    (when (zerop port) (error "No port binding"))
    (let ((conn (rpc-connect host port)))
      (make-client-queue :conn conn
			 :id 0
			 :handle handle))))

(defun close-queue (q)
  "Close the previously opened queue."
  (declare (type client-queue q))
  (rpc-close (client-queue-conn q)))

(defun post-message (queue data &optional id)
  "Post a message to the queue. Returns immediately, does not acknowledge the server received the message.

ID ::= if supplied, is an integer to be used as the message id, otherwise an autogenerated id will be used.

Returns the ID of the message sent to the queue."
  (declare (type client-queue queue))
  (unless id 
    (incf (client-queue-id queue))
    (setf id (client-queue-id queue)))
  (call-post (client-queue-handle queue)
	     id
	     data
	     :connection (client-queue-conn queue)
	     :timeout nil)
  id)
	     
;; ----------------------------

(defun handle-dump (void)
  (declare (ignore void))
  (mapcar (lambda (q)
            (list :handle (mq-handle q)
                  :seqno (mq-seqno q)))
          *mqlist*))

(defrpc call-dump 2
  :void
  (:varray (:plist :handle :uint32 :seqno :uint32))
  (:documentation "List all available message queues.")
  (:handler #'handle-dump)
  (:program rpcmq 1))


;; ------------------------------

(defun discover-queues ()
  "Broadcast a discovery message to the local network to 
discover available frpcmq services. Returns a list of (host port quues)."
  (let ((hosts (frpc.bind:call-callit (program-id 'rpcmq) 1 2 nil
                                      :host "255.255.255.255"
                                      :protocol :broadcast)))
    (mapcar (lambda (h)
              (destructuring-bind (host (port buffer)) h
                  (list host port (unpack #'%read-call-dump-res buffer))))
            hosts)))

