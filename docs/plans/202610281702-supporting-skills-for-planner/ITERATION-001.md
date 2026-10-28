When planning iterations there are skills that could be useful for the agent to use, for example how best to write git commits or how to run yarn commands. I want the canonical version of these still to be with the planner code and installed into the global skills using `planner skills install`.

The command will copy the skills from the ruby gem to the `.claude/skills` folder where the command is ran.
An optional `--global` can be passed which will install the skills to `$HOME/.claude/skills`

Using `planner skills list` will list a all skills that planner has.
Using `planner skills install --only=slug1,slug2` will limit what is installed.
Using `planner skills install` when the skill exist will show a confirmation listing what will be overrridden. It will only complete the operation if the user confirms.

The shape of the `planner skills` command is up for iteration and can be changed if there is a better layout for the sub command. Whatever option is chosen it should be open to expansion later

