I have been using the `plans` command to manage my coding agent workflow. I am now looking to make this more formal and allow further improvements over time with an updated `planner` command

This repo will implement this command.

I want to start with replicating the existing `plans` bash script with a new cli application in this repo. The current bash script it available in @docs/examples/plans
The skill that is currently used for planing an iteration is available in @docs/examples/plan-from-iteration-skill.md

I want this command to be extendable so I can make changes confidently in the future.

My agent workflow works like this
- Create a plan folder for related prompts and files
- Create an iteration file with prompt. 
- Use the `plan-from-iteration` to turn the plan into a prompt
- Send the plan to the agent to build.

In future I expect to add more to the run command to add post run static checks or move this to a factory be it self built or another tool.
