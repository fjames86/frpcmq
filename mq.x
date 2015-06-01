
struct mq_info {
  unsigned int handle;
  unsigned int seqno;
};


struct mq_post_arg {
  unsigned int handle;
  unsigned int id;
  opaque data<>;
};

typedef mq_info mq_dump_res<>;

program MQPROG {
  version MQV1 {

    void
    MQ_NULL( void ) = 0;
    
    void 
    MQ_POST( mq_post_arg ) = 1;
    
    mq_dump_res
    MQ_DUMP( void ) = 2;

  } = 1;
} = 0x2666385D;
