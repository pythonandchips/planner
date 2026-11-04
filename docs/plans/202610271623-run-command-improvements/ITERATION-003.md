The run command is to restrictive in its instruction to do only what the plan files tells it. It causes the run to stop on failing tests that the agent should fix.

We need to update the run prompt to allow the agent to investigate and fix failing tests.
The agents should stop on a failing test when it is due to environment issues such as cannot connect to database
