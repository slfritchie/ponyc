#!/usr/bin/env dtrace -x aggsortkey -x aggsortkeypos=0 -s

/*
 * This script only tracks user actor -> user actor messages.
 *
 * Messages such as ACTORMSG_ACK and ACTORMSG_CONF (see telemetry.d)
 * aren't caused directly by Pony code that is visible to the
 * programmer.
 */

inline unsigned int UINT32_MAX = 4294967295;
inline unsigned int ACTORMSG_APPLICATION_START = (UINT32_MAX - 7);
inline unsigned int ACTORMSG_BLOCK = (UINT32_MAX - 6);
inline unsigned int ACTORMSG_UNBLOCK = (UINT32_MAX - 5);
inline unsigned int ACTORMSG_ACQUIRE = (UINT32_MAX - 4);
inline unsigned int ACTORMSG_RELEASE = (UINT32_MAX - 3);
inline unsigned int ACTORMSG_CONF = (UINT32_MAX - 2);
inline unsigned int ACTORMSG_ACK = (UINT32_MAX - 1);

inline unsigned int SMALLEST_ACTORMSG = ACTORMSG_APPLICATION_START;

BEGIN
{
  printf("Column headings: actor id, msg-in|msg-out, =, count\n");
  printf("\n");
}

pony$target:::actor-msg-send
/arg1 < SMALLEST_ACTORMSG/
{
  @all[arg3, "msg-in"] = count();
}

pony$target:::actor-msg-run
/arg2 < SMALLEST_ACTORMSG/
{
  @all[arg1, "msg-out"] = count();
}

tick-1sec
{
  printa("%12d %-7s = %@12d\n", @all);
  printf("\n");
  clear(@all);
}

END
{
  printa("%12d %-7s = %@12d\n", @all);
  printf("\n");
}
