# aider for DESY

This repository contains bash scripts aimed at safely and effectively using the DESY assistant with aider.
It assumes that you have your own installation of aider, and have set up the api keys for the DESY assistant (see the section on setting up).
It is still very much in "alpha", and feedback is most welcome.

For the sake of proper compliance, please make sure you have done the AI safety training.


## Set up

This goes through a setup, explaining each step well enough that you can hopefully fix anything that doesn't work out of the box, or go quite to script on your system.

### Get api keys

The official instructions for this are here; [it.desy.de/services/desy_assistant](https://it.desy.de/services/desy_assistant/index_eng.html);
search this page for "I would like to use DESY Assistant as a model provider in a local AI chat tool." and expand the corresponding section.

Just for completeness, as of today's date the process is;

1. Be in the desy internal network, or connected via vpn.
2. Go to [assistant.desy.de](assistant.desy.de).
3. Click the "profile picture" in the top right and select "Settings" from the drop down menu.
4. When the settings window pops up select the "Account" tab on the left.
5. Click "show" by the "API keys" option, and generate a new key.

### Safely store api keys

While it's perfectly possible to store your api keys in plain text it's a bad idea.
Github is being constantly scanned for leaked secrets like api keys, and AI has in general accelerated the pace of cyber attacks.
Using `gpg` to store and retrieve secrets is very portable, safe, and easy.
Inside this repository is a script called `secret.sh`, it's a wrapper for using `gpg` to store your api keys (but would work equally well on anything password adjacent).

To store your new api key;

1. Make the script executable; `chmod +x secret.sh`
2. Use it to store your key; `./secret.sh set desy`
3. When prompted to `Enter secret for "desy":` give it the api key. Then set a password in the pop-up.
4. Check you can retrieve it with `./secret.sh get desy`

You can see the file you created at `~/.secrets/desy.gpg` -- that's your encrypted api key.

Aside, if you have your own solution for storing secrets at the cli,
this can be easy implemented by altering the `_get_api_keys()` method in `bash_functions.sh`.

### Install aider

Now you need aider itself. 
Generic download instructions are on the website [aider.chat](aider.chat).
I recommend you use a conda environment for your own future sanity.

```bash
conda create --name aider
conda activate aider
conda install pip
python -m pip install aider-install
aider-install
```

I also recommend you adopt the conf files given in this repository.
To allow aider to find them automatically go to your home directory and link them from there;

```bash
cd ~
ln -s /path/to/this/repository/aider_for_desy/confs/.aider.conf.yml
ln -s /path/to/this/repository/aider_for_desy/confs/.aider.model.metadata.json
ln -s /path/to/this/repository/aider_for_desy/confs/.aider.model.settings.yml
```

This will set some sane defaults, and give aider a bit of information about desy (and blablador) models.
Some of this information I have estimated, because it's not all published.
Note that the costs of desy models are not "real", they are my estimate of what that service might be costing desy to provide, you aren't actually going to get a bill.

Now that all this is done, you could give aider a quick try with the desy service;

```bash
conda activate aider  # if you didn't already
aider  --openai-api-key=$(./secret.sh get desy) \  # pass api key straight to aider
       --openai-api-base=https://assistant.desy.de/api/ \  # tell aider where api is
       --model=openai/reasoning  # tell aider which model you want
```

It that worked you should see something like;
```
─────────────────────────────────────────────────────────────────────────────────────────────────────────
exist. Skipping.
Aider v0.86.3.dev+import
Model: openai/reasoning with whole edit format
Git repo: .git with 16 files
Repo-map: using 4096 tokens, auto refresh
─────────────────────────────────────────────────────────────────────────────────────────────────────────
>
```

Press control-c twice to exit.

### Test function wrappers and add to `.bashrc`

explain the function wrappers
try it with the function wrappers

## Basic usage

Remember you need to be in the internal network/have a vpn
Launch in a repository

Launch options, assuming you are using the function wrappers

Editing in files

### Docs for aider


## Adding more model apis

need to add models to the json
if you want to use the function wrappers


