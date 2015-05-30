# frpcmq
frpc based message queue.

Provides a simple asynchronous message queue type semantics using rpc. Mainly a toy at the moment, but could be useful at some point.

## 1. Usage

```
;; on the server, create the queue
CL-USER> (defparameter *q* (frpcmq:create-queue "myqueue"))
;; block until a message arrives
CL-USER> (frpcmq:get-message *q*)

;; on the client, get a handle to the remote queue 
CL-USER> (defparameter *handle* (frpcmq:call-open "myqueue"))
;; send a message
CL-USER> (frpcmq:call-post *handle* #(1 2 3 4))
1

;; the server now receives the message
CL-USER> (frcpmq:get-message *q*)
#(1 2 3 4)
1

;; the server may alternatively work in a non-blocking fashion
;; note that it is now up to the server to decide how long to wait 
;; until polling the queue again
CL-USER> (do ((start (get-universal-time))
              (now (get-universal-time) (get-universal-time)))
             ((> now (+ start 60)))
           (multiple-value-bind (data id) (frpcmq:get-message *q* t)
             (if data 
                (format t "~D ~S~%" id data)))
           (sleep 1))
```

## 2. License
Licensed under the terms of the MIT license.

Frank James
May 2015.
