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


### Install aider

download
link the confs to your home dierctory

try it out without the function wrappers - you always need internal network/vpn

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


