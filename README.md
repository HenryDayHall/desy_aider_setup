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

In this repository is a script called `bash_function.sh` which contains some quality of life bash functions. It is intended to;

- Allow you to switch quickly between DESY and blablador if you use both. They have different api enprints, so you can only have one at a time.
- Generate some quick and sensible defaults for DESY and blablador models.
- Mix and match with claude models if you desire.

You can give it a try now;

```bash
source bash_functions.sh
aider_desy  # will start your conda enviroment and add all sensible flags
```

Hopefully that just started? If so, your setup is working; press control-c twice to exit.
You can keep doing `source bash_functions.sh`, or you can add that line to your `~/.bashrc` so that it happens automatically in every shell you start.

## Basic usage

First of all, remember you need to be in the internal network or have the DESY vpn active to access the DESY assistant api.
If you don't it will just hang.

Secondly, it's normally a good idea to launch aider in a git repository.
It's designed to look at, and alter, only files in that repository.
If you launch aider and you aren't in a git repository it will suggest you start one, and you might not be where you intended to put the root of your repository.

### cli arguments

I'm going to discuss cli options, assuming you are using the function wrappers.
A basic start would be just `aider_desy`, but you might want to customise some things.

Firstly, the models can be changed; aider employs 3 different models;

1. Primary model (reasoning, architecture).
2. Editor model (should be good at writing code and files).
3. Weak model (summarising the chat and making the repo map).

By default, I give DESY's "reasoning" model for all 3, but if you want, there are other options.
You can see them all by doing `extract_model_names desy`.
Then to set specific models;
```bash
aider_desy <primary> <editor> <weak>
```
For example; `aider_desy reasoning coding desy-assistant`. 
The names of these models should autocomplete with tab.

Finally, and flags given to this function wrapper will be passed straight to aider.
This works with or without models specified.

### Usage modes

Aider's [own docs](https://aider.chat/docs/usage.html) are the best place to look for advice on usage, but here a couple of quick tips to get started.

You can `\ask` aider to tell you things, and it won't change any files;

```bash
aider_desy
─────────────────────────────────────────────────────────────────────────────────────────────────────────
exist. Skipping.
Aider v0.86.3.dev+import
Model: openai/reasoning with whole edit format
Git repo: .git with 16 files
Repo-map: using 4096 tokens, auto refresh
─────────────────────────────────────────────────────────────────────────────────────────────────────────
> /ask Can you see where the data loader is in this repository?
```

If you don't ask, aider may make some file changes if it interprets your question as an instruction.

```bash
aider_desy
...
─────────────────────────────────────────────────────────────────────────────────────────────────────────
> The data loader struggles with larger files, how can we improve this?
```

You can also "invoke" aider from your editor.
First, add the file you want it to work on

```bash
aider_desy
...
─────────────────────────────────────────────────────────────────────────────────────────────────────────
> /add src/data/dataloader.py
```

Then with `src/data/dataloader.py` open in your editor, write a comment (must begin with `#` or `\\`) ending with `AI!`, then save the file.
For example;

```python
import numpy as np

class DataLoader():
    def __init__(self, file_name):
        self.file_name = file_name
        # check the file exists and throw a warning if not AI!
    
    def _open(self):
        self._loaded = np.load(file_name)
```

You should see some chatter in the aider window. Something a bit like;
```bash
Processing your request...
---------------------------------------------------------------------------------------------------------

► THINKING

We need to interpret the AI comment: "check the file exists and throw a warning if not AI!" The comment
is in init. It says to check the file exists and throw a warning if not. The comment also says "AI!" at
the end, but that's likely just a marker. We need to implement the check: use os.path.exists or similar.
If file does not exist, issue a warning (maybe using warnings.warn). Also need to fix _open: it uses
file_name but should be self.file_name. Also need to import os and warnings. Then remove the AI comment.

We'll produce updated dataloader.py.

Also note: The class name is DataLoader, but the file is dataloader.py. That's fine.

We'll add import os, warnings. In init, after setting self.file_name, check if not
os.path.exists(self.file_name): warnings.warn(f"File {self.file_name} does not exist."). Then remove the
comment.

In _open, change file_name to self.file_name.

Return entire file.

Let's write.

---------------------------------------------------------------------------------------------------------

► ANSWER

dataloader.py


 @@ -1,9 +1,12 @@
  import numpy as np
 +import os
 +import warnings

  class DataLoader():
      def __init__(self, file_name):
          self.file_name = file_name
 -        # check the file exists and throw a warning if not AI!
 +        if not os.path.exists(self.file_name):
 +            warnings.warn(f"File {self.file_name} does not exist.")

      def _open(self):
 -        self._loaded = np.load(file_name)
 +        self._loaded = np.load(self.file_name)


Tokens: 2.9k sent, 313 received. Cost: $0.00049 message, $0.00049 session.
Applied edit to dataloader.py
─────────────────────────────────────────────────────────────────────────────────────────────────────────
```

Now reload your file in the editor (if you editor doesn't automatically reload on changes).
You can see that aider has directly written the changes into the file.


## Adding more model apis

TODO
need to add models to the json
if you want to use the function wrappers


