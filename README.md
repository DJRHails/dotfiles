<div align="center">
  
  ![Delta Logo](docs/delta.svg)
  
</div>

<h1 align="center">
  <strong>.files</strong>
</h1>

`.files` will sanely setup a machine, and provide quality of life improvements.

## :gear: Installation
```bash
git clone https://github.com/DJRHails/dotfiles.git ~/.files
cd ~/.files
./bootstrap.sh --cli --yes

# Custom config
./bootstrap.sh
```

<div align="center">

![Installation Example](docs/dotfiles.gif)

</div>

## :package: Modules

| Module                 | Description 
| ---------------------- | -----------
| `atom`                 | Setup atom text editor with packages & keymap.
| `code`                 | Setup VSCode text editor with sane settings.
| :construction: `docker`| Install docker.
| `flutter`              | Install flutter and setup PATH.
| :sparkle: `git`        | Adds git aliases, auto-complete, sets up user-level config and link this machines ssh to github.
| `hyper`                | Install hyper terminal editor and config.
| :construction: `java`  | Adds JAVA Path.
| `mouse`                | Remaps mouse special keys to Copy and Paste.
| `pentest`              | Provides a few aliases which are useful in penetration tests / deobfuscation.
| `python`               | Add python3, some nice default installations, and aliases for virtual environment.
| `rust`                 | Install Rust and Cargo.
| :sparkle: `ssh`        | Install ssh config for commonly used machines.
| `sunshine`             | Emulate macos theme changes against time.
| `vim`                  | Install vim & vim config.
| :sparkle: `zsh`        | Install zsh terminal, setup aliases, autocompletion and generally enabling a lot of the functionality above.

## :zap: Inspired by
- [@holman](https://github.com/holman/dotfiles)
- [@alrra](https://github.com/alrra/dotfiles)
- [@denisdoro](https://github.com/denisidoro/dotfiles)
