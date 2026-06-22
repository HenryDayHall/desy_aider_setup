# What to learn

Map of topics to learn about regarding use of LLM assistant tools.
Need to understand, document, develop personal implementations and practice.

Need to keep track of how much time is spent on this, v.s. how much efficiency it gains.
This requires having predictions about what I could achieve in the next 6 months compared to actual progress.

- For the first week, just play. Results are unimportant.
- For the first 2 months, try to balance getting at least as much out as would be expected without other tasks.
- Ongoing monitoring of predicted v.s. Attained. 


## Predictions

Upcoming tasks are

1. LLM based foundation models
    a) Ensure that SPADE runs on a dataset for calorimeters
    b) Potentially expand calorimeter dataset
    c) Add angular conditioning for SPADE
    d) Identify and understand jet level dataset
    e) Get SPADE running on jet level data
    f) Define and assess some jet level validation
    g) transfer learning
2. Mixture of specialists hybrid improved model.
    a) Get AllShowers attention component running on the pure Hadronic
    b) Experiment with CC3 diffusion to generate the EM components
    c) Create PointFlow to setup events (should it do EM only after hadronic is designed?)
    d) Run together and evaluate
3. EAS
    a) Manageable data loader and format.
    b) basic generation model
    c) good validation criteria
    d) integration into CORSIKA

My expectation is that, with no AI, I could complete 2 and make some progress on 1 by the end of the year.
In the next 2 months, I would anticipate covering 1 > a, b & c and 2 a.
If I manage the same with AI in the next 2 months, I will consider the AI a success.

## Starting points

What should be covered right away, before I return to other projects.

- Subscription to at least one LLM. Potentially 2.
    * Start by trying just Claude.
    * Consider also perplexity.
    * Monitor and take notes on use of both over 2 months.
- basic language server for vim?
- Integration methods for LLM and editor. Try multiple
    * aider
    * Claude's native?
- Integration methods for LLM an Jupyter Notebooks
    * might have to change from jhub to manually launching.

## Near term

What should be done over the next 2 months.

- BabyAGI, learn a bit more about the internals
- Experiments with langchain to customise solutions
- Blog post about this
- Good ways to store long term project conversations.
- Demonstrate difference in ability of DESY AI and Claude

## Long term objectives

What I would like to attempt eventually.

- Custom Aider or langchain setup for integrating and talking with LLMs 
- Soft prompts to remember progress on long term tasks
- Integration with emails
- Time management prompting
- Learning which LLM to use when
- More online records

