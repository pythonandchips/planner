I want a new command that will create summaries of plan, review and finding files. 

The command will take a brief and create a summary of the requested document.
Unlike other command the brief will be given via the command line only. 

A summary uses the information in the given file to create the summary.
It can only use information from outside or other files if it is need to support the summary.
Other data used in the summary must be given a full reference.

Unless state otherwise in the brief the output will be returned in the agent.
If asked to write the summary to disk write it to SUMMARY-<number>.<ext> or if the output is not a single file write it to SUMMARY-<number> folder.

Example outputs that the user might ask for:
- Sequence diagram 
- Audio recording
- Animated Gif
- Markdown file
- Slide deck

