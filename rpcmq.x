
enum mqstatus {
  MQ_OK,
  MQ_NOTFOUND = 1,
  MQ_ERROR = 2
};

union mq_res switch(mqstatus stat) {
  case MQ_OK: unsigned int handle;
  default: void;
};

struct mqinfo {
  unsigned int handle;
  string name<>;
  unsigned int id;
};

union stat_res switch(mqstatus stat) {
  case MQ_OK: mqinfo info;
  default: void;
};

struct postinfo {  
  unsigned int handle;
  opaque data<>;
};

typedef string mqopen_arg<>;

typedef mqinfo mqdump_res<>;

program MQPROG {
  version MQV1 {

    void
    mqnull( void ) = 0;
    
    mq_res 
    mqopen( mqopen_arg ) = 1;

    mq_res
    mqpost( postinfo ) = 2;

    stat_res 
    mqstat( unsigned int ) = 3;
    
    mqdump_res
    mqdump( void ) = 4;

  } = 1;
} = 0x2666385D;
