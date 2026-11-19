The readme has become untidy and is in need of improvement I want to

- Update the first paragraph with the workflow that the planner tool is created to manage. I'll define the workflow below. 
- Tidy up the install instructions, remove the line on mise and add a git clone as the first step
- Add contribution guidelines at the bottom of the read me. This should include a line that all PR must include a iteration and a plan created with planner
- Usage is currently hard to read and overely verbose. Re-organise to make it easier to read

## workflow

- Explore (optional); have an agent explore the codebase and gather context for the upcoming task.
- Plan; Give the agent a specific task you want to complete and shape the solution
- Review (optional); have an agent review the plan and give recommendations on what could be improved. This can also look at specific aspects like security, performance through the lenses
- Run; Apply the plan to the codebase
