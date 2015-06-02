# frpcmq
frpc based message queue.

Provides a simple asynchronous message queue type semantics using rpc. Mainly a toy at the moment, but could be useful at some point.

## 1. Usage

It should be used in a client/server manner. The server creates the queue and then waits for messages to arrive. The client
opens the remote queue and sends messages to it. There is no guarantee of delivery.

### 1.1 Example

```
;; on the server, create the queue
CL-USER> (defparameter *q* (frpcmq:create-queue 123123))
;; block until a message arrives
CL-USER> (frpcmq:get-message *q*)

;; on the client, get a handle to the remote queue 
CL-USER> (defparameter *c* (frpcmq:open-queue "localhost" 123123))
;; post a message to the queue. returns immediately, does not guarantee that the server received the message
CL-USER> (frpcmq:post-message *c* #(1 2 3 4))

;; the server now receives the message
CL-USER> (frcpmq:get-message *q*)
#(1 2 3 4)
1

;; the server may block until a message is received with a timeout
CL-USER> (frpcmq:get-message *q* nil 1)
nil

;; the server may alternatively work in a non-blocking fashion
;; note that it is now up to the server to decide how long to wait 
;; until polling the queue again
CL-USER> (do ((start (get-universal-time))
              (now (get-universal-time) (get-universal-time)))
             ((> now (+ start 60)))
           (multiple-value-bind (data id) (frpcmq:get-message *q* t)
             (if data 
                (format t "~D ~S~%" id data)
                (sleep 1))))
```

### 1.2 Discovery
You may use `DISCOVER-QUEUES` function to discover frpcmq services on your network. This function
broadcasts to the portmap CALLIT function. The function returns a list of (host port queues) for 
each discovered host.

```
CL-USER> (discover-queues)
((#(10 1 1 1) 47831 ((:handle 123321 :seqno 32))) (#(10 1 2 4) 56482 ((:handle 123321 :seqno 22))))
```

## 2. Other languages
Compile the xfile using rpcgen to create a skeleton program for use with the C programming language:

```
$ rpcgen -a mq.x
$ make -f Makefile.mq
```

You can use this as a starting point to call to Lisp from C. 

## 3. License
Licensed under the terms of the MIT license.

Frank James
May 2015.
