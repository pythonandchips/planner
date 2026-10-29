I want to create a git commit skill which ensure commit messages match expectations.

The skill is to ensure the content of the commit follows these rules
- Use plain english throughout
- Have a attribution line of Assisted-by: <name of agent and model>
- The body must explain what has changed, why it has changed not how it was changed


Additionally the format of the commit message must follow these rules
- Limit subject line to 50 characters
- Capitalize the subject line
- Do not end subject line with a period
- Wrap the body at 72 characters


Use the `skill-creator` sill to help build the skill as part of the run stage
This skill will be installed by `planner`


