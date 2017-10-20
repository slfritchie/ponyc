#!/usr/bin/env dtrace -x aggsortkey -x aggsortkeypos=0 -q -s

/*
 * TODO
 */

/* TODO: delete? edit? */
inline unsigned int UINT32_MAX = 4294967295;
inline unsigned int ACTORMSG_APPLICATION_START = (UINT32_MAX - 7);  /* -8 */
inline unsigned int ACTORMSG_BLOCK = (UINT32_MAX - 6);              /* -7 */
inline unsigned int ACTORMSG_UNBLOCK = (UINT32_MAX - 5);            /* -6 */
inline unsigned int ACTORMSG_ACQUIRE = (UINT32_MAX - 4);            /* -5 */
inline unsigned int ACTORMSG_RELEASE = (UINT32_MAX - 3);            /* -4 */
inline unsigned int ACTORMSG_CONF = (UINT32_MAX - 2);               /* -3 */
inline unsigned int ACTORMSG_ACK = (UINT32_MAX - 1);                /* -2 */

inline unsigned int SMALLEST_ACTORMSG = ACTORMSG_APPLICATION_START;

BEGIN
{
  printf("Column headings:    thread #, msg id, msg-in|msg-out, =, count\n");
  printf("Special thread #s: KQUEUE=-10, IOCP=-11, EPOLL=-12,\n");
  printf("\n");
}

pony$target:::thread-msg-push
{
  this->msg_id = arg0;
  this->thread_from = arg1;
  this->thread_to = arg2;
  @all[this->thread_to, this->msg_id, "msg-in"] = count();
}

pony$target:::thread-msg-pop
{
  this->msg_id = arg0;
  this->thread = arg1;
  @all[this->thread, this->msg_id, "msg-out"] = count();
}

tick-1sec
{
  printa("%3d %3d %-7s = %@12d\n", @all);
  printf("\n");
  clear(@all);
}

END
{
  printf("Final:\n");
  printa("%3d %3d %-7s = %@12d\n", @all);
  printf("\n");
}
