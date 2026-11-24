The plan command adds a commit message for the run command to use. The instructions around this are to tight as it will often commit with the wrong attribution using the planner model instead of the run model.

I want to change this so that the commit message will include an attribution for the model that planned the commit, the model for review (if a review took place) and the model that ran the plan. Each of these models will be on a separate `Assisted-by` command. 

We must ensure this is compatible with the `commit-message` skill and the 2 instructions will not conflict
