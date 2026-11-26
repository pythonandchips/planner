We send code changes to github for review by other engineers and coding agents.

I want a command that will download comments from a given PR, write the comments to an iteration file and then plan a fix for the comments.

The planning should follow the existing plan prompt.

To download the data the command can use `gh` cli app which the user will install separately

This comes from the following TODO item

- Pull PR review comments into the iteration file or plan when a brief points at a pull request, for example with a `planner feedback <pr>` command. The folder should make sense without GitHub.
