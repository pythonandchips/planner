I am wanting to use the `planner run` command as part of a software factory. For this we will want planner to return the prompt it will run to stdout so that we can pass the prompt to the factories own claude commad

Add an option to execute the prompt with the `-p` and `--print` to run so that it will output the prompt so it can be read.
Ideally it will put the output in the following format to stdout

```
{
  prompt: "...",
  allowedTools: [...]
}
```

Where the prompt is the text planner would send to claude and allowed tools are all the tools the prompt requires. This can be a hard coded list that for now based on this session as it has the same tools as `run`
