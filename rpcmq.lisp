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
           #:call-open
           #:call-post
           #:call-stat
           #:call-dump

           #:get-message
           #:create-queue
           #:delete-queue

	   #:rpcmq-error
	   #:queue-not-found-error))

(in-package #:frpcmq)

;; a random program number I generated
(defprogram rpcmq #x2666385D)

(defxenum mqstat 
  (:ok 0)
  (:notfound 1)
  (:error 2))

(define-condition rpcmq-error (error)
  ()
  (:report (lambda (c stream) 
	     (declare (ignore c))
	     (format stream "RPCMQ-ERROR"))))

(define-condition queue-not-found-error (rpcmq-error)
  ()
  (:report (lambda (c stream) 
	     (declare (ignore c))
	     (format stream "RPCMQ queue not found"))))

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
  name handle id messages 
  lock condv)

(defvar *mqlist* nil
  "List of message queues.")

(defun find-queue (name-or-handle)
  (etypecase name-or-handle 
    (string (find name-or-handle *mqlist* 
                  :key #'mq-name 
                  :test #'string-equal))
    (integer (find name-or-handle *mqlist*
                   :key #'mq-handle
                   :test #'=))))

(defun create-queue (name)
  "Create a new message queue.
NAME ::= name to reference the queue.

If a queue with that name already exists it returns that queue, otherwise allocates a new queue."
  (declare (type string name))
  (let ((q (find-queue name)))
    (when q 
      (return-from create-queue q)))
  (let ((q (make-mq :handle (random (expt 2 32))
                    :id 0
                    :lock (bt:make-lock)
                    :condv (bt:make-condition-variable)
                    :name name
                    :messages (make-queue))))
    (push q *mqlist*)
    q))

(defun delete-queue (q)
  "Delete the queue."
  (declare (type mq q))
  (setf *mqlist*
        (remove q *mqlist*)))

(defun get-message (q &optional return-immediately timeout)
  "Receive a message from the queue. 
Q ::= a message queue returned from a previous call to CREATE-QUEUE.

RETURN-IMMEDIATELY ::= if true, will will return immediately with value nil if no messages are available. Otherwise will block until a message arrives.

TIMEOUT ::= time to wait in seconds for a message. If the timeout expires returns nil.

Returns (values data id)."
  (declare (type mq q))
  (bt:with-lock-held ((mq-lock q))
    (let ((m (dequeue (mq-messages q))))
      (cond
        (m
         (values (message-data m) (message-id m)))
        (return-immediately 
         ;; if we don't want to block then ensure there are messages, otherwise return immediately 
         nil)
        (t 
         ;; block until the condition varaible is signalled
         (if timeout
	     (handler-case (bt:with-timeout (timeout) (bt:condition-wait (mq-condv q) (mq-lock q)))
	       (bt:timeout () (return-from get-message nil)))
	     (bt:condition-wait (mq-condv q) (mq-lock q)))
         (let ((m (dequeue (mq-messages q))))
           (values (message-data m) (message-id m))))))))

;; ------------------------------------


(defun handle-open (name)
  (let ((q (find-queue name)))
    (if q 
        (make-xunion :ok (mq-handle q))
        (make-xunion :notfound nil))))

(defrpc call-open 1 
  :string
  (:union mqstat
          (:ok :uint32)
          (otherwise :void))
  (:arg-transformer (name)
                    name)
  (:transformer (res)
    (case (xunion-tag res)
      (:ok (xunion-val res))
      (:notfound (error 'queue-not-found-error))
      (t (error 'rmcpq-error))))
  (:program rpcmq 1)
  (:handler #'handle-open)
  (:documentation "Open a handle to the remote message queue. 
NAME ::= name of the message queue. 

Returns a handle to use in subsequent calls."))

;; -----------------------------

(defun handle-post (arg)
  (destructuring-bind (handle data) arg
    (let ((q (find-queue handle)))
      (cond
        (q 
         (bt:with-lock-held ((mq-lock q))
           (incf (mq-id q))
           (enqueue (make-message :id (mq-id q) :data data)
                    (mq-messages q)))
         ;; signal the condition variable 
         (bt:condition-notify (mq-condv q))
         ;; return the id 
         (make-xunion :ok (mq-id q)))
        (t 
         (make-xunion :notfound nil))))))

(defrpc call-post 2
  (:list :uint32 (:varray* :octet))
  (:union mqstat
          (:ok :uint32)
          (otherwise :void))
  (:arg-transformer (handle data) (list handle data))
  (:transformer (res) 
    (case (xunion-tag res)
      (:ok (xunion-val res))
      (:notfound (error 'queue-not-found-error))
      (t (error 'rmcpq-error))))
  (:program rpcmq 1)
  (:handler #'handle-post)
  (:documentation "Post a message to the remote message queue."))

;; -------------------------------

(defun handle-stat (handle)
  (let ((q (find-queue handle)))
    (if q
        (make-xunion :ok
                     (list :handle (mq-handle q)
                           :name (mq-name q)
                           :id (mq-id q)))
        (make-xunion :notfound nil))))

(defxtype* mqinfo () (:plist :handle :uint32 :name :string :id :uint32))

(defrpc call-stat 3
  :uint32 
  (:union mqstat
          (:ok mqinfo)
          (:otherwise :void))
  (:program rpcmq 1)
  (:arg-transformer (handle) handle)
  (:transformer (res)
    (case (xunion-tag res)
      (:ok (xunion-val res))
      (:notfound (error 'queue-not-found-error))
      (t (error 'rmcpq-error))))
  (:handler #'handle-stat)
  (:documentation "Get information on the remote message queue."))

;; ----------------------------

(defun handle-dump (void)
  (declare (ignore void))
  (mapcar (lambda (q)
            (list :handle (mq-handle q)
                  :name (mq-name q)
                  :id (mq-id q)))
          *mqlist*))

(defrpc call-dump 4
  :void
  (:varray mqinfo)
  (:documentation "List all available message queues.")
  (:handler #'handle-dump)
  (:program rpcmq 1))


