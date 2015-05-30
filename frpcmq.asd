;;;; Copyright (c) Frank James 2015 <frank.a.james@gmail.com>
;;;; This code is licensed under the MIT license.

(asdf:defsystem :frpcmq
  :name "frpcmq"
  :author "Frank James <frank.a.james@gmail.com>"
  :description "A simple message queue using frpc."
  :license "MIT"
  :components
  ((:file "rpcmq"))
  :depends-on (:frpc))


