# frpcmq
frpc based message queue.

Provides a simple asynchronous message queue using RPC. 

## 1. Usage

It should be used in a client/server manner. The server creates the queue and then waits for messages to arrive. The client
opens the remote queue and sends messages to it. There is no guarantee of delivery.

### 1.1 Examples
Several example usages follow.

#### 1.1.1 Server 

The server first starts an RPC server:
```
CL-USER> (defparameter *s* (frpc:make-rpc-server))
CL-USER> (frpc:start-rpc-server *s*)
```

Now the server creates a queue and starts waiting for messages to arrive
```
CL-USER> (defconstant +myqueue+ 123321)
CL-USER> (frpcmq:create-queue +myqueue+)
CL-USER> (do (done)
             (done)
           (multiple-value-bind (data id) (frpcmq:get-message *q*)
             (when (zerop id) (setf done t))
             (format t "~D ~S~%" id data))
           (sleep 1))
```

#### 1.1.2 Client

The client must first locate the server which hosts the queue they wish to send the message to:
```
CL-USER> (frpcmq:discover-queues)
((#(10 1 1 1) 47831 ((:handle 123321 :seqno 32))) (#(10 1 2 4) 56482 ((:handle 333222 :seqno 22))))
```

So host "10.1.1.1" hosts the queue we are interested in. Create a client-side queue object to send
the messages to:
```
CL-USER> (defparameter *q* (frpcmq:open-queue "10.1.1.1" +myqueue+))
```

Start sending messages:
```
CL-USER> (dotimes (i 10) (frpcmq:post-message *q* #(1 2 3 4 5 6 7)))
```

Send a message with ID 0 which our server interprets to mean to terminate:
```
CL-USER> (frpcmq:post-message *q* #(1 2 3 4 5 6 7) 0)
```

Notice that we send all our messages immediately, but the server takes 1 second to process each message.

#### 1.1.3 Non-blocking server
 
The server may alternatively work in a non-blocking fashion, so that `get-message` returns immediately if 
there are no message available (the default behaviour is to block until a message arrives). Note that it
is now the user's responsibility to decide when to wait until checking the queue again.

```
CL-USER> (do ((start (get-universal-time))
              (now (get-universal-time) (get-universal-time)))
             ((> now (+ start 60)))
           (multiple-value-bind (data id) (frpcmq:get-message *q* t)
             (if data 
                (format t "~D ~S~%" id data)
                (sleep 1))))
```

#### 1.1.4 Blocking with a timeout

The server may alternatively wait for a message with a timeout:
```
CL-USER> (frpcmq:get-message *q* nil 1)
nil
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
