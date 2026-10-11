#!/bin/zsh
set -u
print 'Apple Rosetta is needed to run the Intel Wine engine on this Mac.'
print 'Apple will ask you to review and accept its license below.'
/usr/sbin/softwareupdate --install-rosetta
task_install_result=$?
if (( task_install_result == 0 )); then
  print '\nRosetta installed. Return to Mac Games and click Check Setup.'
else
  print "\nRosetta installation did not finish (exit $task_install_result)."
fi
read 'task_close?Press Return to close this window.'
exit "$task_install_result"
