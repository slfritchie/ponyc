#!/usr/bin/env dtrace -x aggsortkey -x aggsortkeypos=0 -q -s

/*
 * Messages such as ACTORMSG_ACK and ACTORMSG_CONF (see telemetry.d)
 * aren't caused directly by Pony code that is visible to the
 * programmer.
 *
 * This script will treat system message IDs as twos-complement and
 * convert them to negative numbers.  See the comments on the right
 * margin to find their negative integer representation.
 */

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
  printf("Column headings:    actor id, msg id (sys msg < zero), msg-in|msg-out, =, count\n");
  printf("System message ids: ACK = -2, CONF = -3, RELEASE = -4,\n");
  printf("                    ACQUIRE = -5, UNBLOCK = -6,\n");
  printf("                    BLOCK = -7, APPLICATION_START = -8\n");
  printf("\n");
}

pony$target:::actor-msg-send
{
  this->msg_id = (arg1 < SMALLEST_ACTORMSG) ? arg1 : (-1 * (arg1 ^ 0xffffffff)) - 1;
  @all[arg3, this->msg_id, "msg-in"] = count();
}

pony$target:::actor-msg-run
{
  this->msg_id = (arg2 < SMALLEST_ACTORMSG) ? arg2 : (-1 * (arg2 ^ 0xffffffff)) - 1;
  @all[arg1, this->msg_id, "msg-out"] = count();
}

tick-1sec
{
  printa("%12d %5d %-7s = %@12d\n", @all);
  printf("\n");
  clear(@all);
}

END
{
  printa("%12d %5d %-7s = %@12d\n", @all);
  printf("\n");
}
