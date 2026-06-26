# Rating assistants

## End goal

Minimise token use and carbon cost while maintaining a high success rate.

Ideally, before a question is sent by aider to a model, and assessment of the suitability of that model for that question is assessed. If the model is unlikely to succeed on this task, or a cheaper model is very likely to succeed, then the user is warned.

This should be extendable, so that additional tweaks can be considered in the future.

This should be learnt from reinforcement learning.

## Edit

Have a base rate guess, that guesses the difficulty and the number of tokens.
Then each conditioned thing is a multiplier of this base.
Encourages the per model architectures to learn about the relationship between model and prompt, rather than just task difficulty.

## Imagined inference

One inference per chat call

One embedding. Embeds;
    - N x Chat context, going back to the last change of task.
    - Settings
    - repo map

Different head for each set of models (main, small, editor);
    - Predicts model rating at end of task from embedding


## Training process

One training step per inference call;
all inference calls in the same task have one target value.

### Workflow for data gathering;

1. User starts aider, aider determines the base directory for output according to the three model names. Inside this directory are output subdirectories.
2. Aider removes any output directories that don't have labels and opens a new output directory for a new task.
3. Aider writes an initial repo map, and settings to the output directory.
4. Each time the user prompts the model, the chat history is written to the output directory.
5. The user sends aider a /task-complete command, with a rating from 0 to 10 as the only argument. Floating point is allowed. Aider writes this argument to the current output directory. 
6. Aider checks if the total size of all files in the output directory. If it's over a limit, the user is warned to start training.
7. Aider opens a new fresh output directory.

Objectives of this is to build up a set of training data from aider usage.
- Each model would ideally have 50GB of data kept
- New data will replace the oldest data as the model's folder fills up

The reinforcement learning program is responsible for actually removing excess data.

### Workflow for reinforcement learning;

We wish to train the embedding with equal number of each model, so even if the new data is 
all one model, we should sample from all model files.

One training step goes like;

1. Identify new data in the model files. Split into batches of up to 8 tasks per model per batch.
2. Balance with random existing data from all other models.
3. Starting from the first message in each task, and sequentially adding messages to the embedding space; get model to reproduce the output scores.

### Evaluation

Periodically, it will be necessary to eliminate model combinations that are not strong or are no longer provided.
This can be done based on actual scores from the user, and cost of calls in tokens.
We want to keep;
- Two best scoring overall
- Two best scoring per token
- Two best scoring free models

Other models will be marked as archive, and potentially removed.

### Predictions 

When the model is performing well, I will let it listen to the output directory, and report performance predictions as tasks are attempted.
