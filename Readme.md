# Table of Content

- [Table of Content](#table-of-content)
- [:warning: Disclaimer :warning:](#warning-disclaimer-warning)
  - [Discords Privacy invasion](#discords-privacy-invasion)
  - [Oracle and my stance](#oracle-and-my-stance)
  - [Self-upgrade not working (14th Jan 2025 - 9th Sept 2025)](#self-upgrade-not-working-14th-jan-2025---9th-sept-2025)
  - [Default x86_64 emulator](#default-x86_64-emulator)
  - [Ubuntu version](#ubuntu-version)
- [Credit](#credit)
- [Instructions](#instructions)
- [Pre-requisite](#pre-requisite)
  - [Windows](#windows)
  - [Mac / Linux](#mac--linux)
- [OCI (Oracle Cloud Infrastructure)](#oci-oracle-cloud-infrastructure)
  - [Creating the VM instance](#creating-the-vm-instance)
  - [Configuring the Network and firewall rules](#configuring-the-network-and-firewall-rules)
- [Connecting to the VM Instance](#connecting-to-the-vm-instance)
  - [Windows](#windows-1)
  - [Mac / Linux](#mac--linux-1)
- [Installing the Valheim Dedicated Server](#installing-the-valheim-dedicated-server)
- [Configuring the Valheim Server](#configuring-the-valheim-server)
- [Starting the Valheim Server](#starting-the-valheim-server)
- [Updating the Valheim Server](#updating-the-valheim-server)
- [Crossplay (Console / Game Pass)](#crossplay-console--game-pass)
- [Modding](#modding)
- [Installer Self-update](#installer-self-update)
- [Adding Pre-existing worlds](#adding-pre-existing-worlds)
- [Installing a world from a .zip file](#installing-a-world-from-a-zip-file)
- [Troubleshooting](#troubleshooting)
  - [Discord](#discord)
  - [Matrix](#matrix)
- [Changing versions](#changing-versions)
  - [Switcing to the Previous Stable Version](#switcing-to-the-previous-stable-version)
  - [Switching to the Public Beta Branch](#switching-to-the-public-beta-branch)
  - [Reverting back to the public version](#reverting-back-to-the-public-version)
- [Oracle and Reclamation of Idle Compute Instances](#oracle-and-reclamation-of-idle-compute-instances)
- [TODOs](#todos)

# :warning: Disclaimer :warning:

## Discords Privacy invasion

With the recent news about Discords age verification system and their third party partner being Persona Identities, I see no reason for staying there.
Persona has ties with Peter Thiel and Palantir which as you probably already know is being used most notably by both ICE and Israel.

I've already stopped my Nitro subscription and intend on disabling my account later this week.  
I've disabled the Discord invite link to this server.  
The server will be put into read-only mode by the middle of the week, then finally delete it before disabling my account.

I've set up a space on [Matrix](#matrix) which you are free to join.

Thank you all for your interest in this project and for staying around.  
Take care and stay safe, hope to see you around. <3

## Oracle and my stance

I've terminated my tenancy with Oracle and I do not intend on going back.
The guide will stay as-is for now but I am considering expanding it further to make it work on different platforms and providers in the future.
I know that server hosting usually cost a pretty penny and a cheap/free server like the ones provided by Oracle are extremely rare. I will still respect you if you want to continue using Oracle to play with your friends.

A [full statement](https://discord.com/channels/242319703660298240/1434191715937554614/1435613328150888658) is available on my [Discord server](#discord).

## Self-upgrade not working (14th Jan 2025 - 9th Sept 2025)

The installer self-upgrade have had a bug in it since 14th of January 2025 where I introduced halt-on-error (see commit [52f55a8f](https://github.com/husjon/valheim_server_oci_setup/commit/52f55a8f563b0c16471cc8afd70e98ec4af9058b)), due to this, the self-upgrade functionality have not worked properly.

If you've used the script since, prior to today (9th of September 2025), you'll have to manually upgrade the script.
This can be done by following the first steps in [Installing the Valheim Dedicated Server](#installing-the-valheim-dedicated-server).

## Default x86_64 emulator

The default x86_64 emulator up until now (21th Sept 2025) has been Box86 and Box64, with the Call to Arms update for Valheim I've decided to replace Box with FEX.
This has been considered for a while as it does seem very stable and in the future should allow for using mods (see [Modding](#modding)).  
It is possible to switch back to using Box by setting the `USE_BOX` environment variable.

For further discussions, please do join my [Matrix space](#matrix).

## Ubuntu version

The installer supports Ubuntu **22.04, 24.04, and 26.04 LTS** on `aarch64`/`arm64` and `amd64`. On ARM, the default emulator is FEX; the legacy Box86/Box64 fallback is available only with `USE_BOX=true` on Ubuntu 22.04 because newer Ubuntu releases changed the 32-bit ARM time ABI.

Ubuntu 26.04 support uses the Ubuntu 24.04 x86_64 FEX guest RootFS. That is intentional: FEX’s prebuilt 24.04 guest is compatible with a 26.04 host, while the host itself remains Ubuntu 26.04. The installer no longer adds the `armhf` architecture on the default FEX path.

After downloading the RootFS, the installer resolves it to an absolute path and exports `FEX_ROOTFS` for SteamCMD, the Valheim server, and server updates. This avoids the FEX error `Current RootFS path set to ''` when FEX has downloaded a RootFS but has not populated its config file.

If an older installation already shows that error, update the setup script and run it once more. It will reuse the existing RootFS, configure the path, and regenerate the launcher/helper environment.

For OCI Ampere instances, choose a **Canonical Ubuntu aarch64** image. OCI’s current documented platform-image list still provides Ubuntu 24.04 and 22.04 for Arm; if Ubuntu 26.04 is not offered in your tenancy, use a custom/imported 26.04 image or use the documented 24.04 image. Do not select the Minimal Ubuntu image for Arm-based shapes; OCI documents the standard Ubuntu image for Arm. See the [OCI platform image list](https://docs.oracle.com/en-us/iaas/Content/Compute/References/images.htm).

Ubuntu 26.04 is the current Resolute Raccoon LTS release; see the [Ubuntu 26.04 release notes](https://documentation.ubuntu.com/release-notes/26.04/).

# Credit

The original guide is from Reddit user That_Conversation_91 on [r/Valheim](https://www.reddit.com/r/valheim/).  
Original post can be found [here](https://www.reddit.com/r/valheim/comments/s1os21/create_your_own_free_dedicated_server)

# Instructions

**Note**: For this guide a free account is required on the Oracle Cloud Infrastructure allowing us to spin up a server which is decently specced.

In this guide, we'll:

- Set up a Virtual Machine using the Oracle Cloud Infrastructure, including firewall rules
- Prepare and use SSH to connect to the Virtual Machine
- Update the Operating System and install the Valheim Dedicated Server software
- Finally we'll use Systemd to allow the server to run automatically.

If you have the knowledge of setting up a server on an alternative cloud provider or your own hardware you may skip ahead to [Installing the Valheim Dedicated Server](#Installing-the-Valheim-Dedicated-Server)

# Pre-requisite

## Windows

To connect to the server in the section [Connecting to the VM Instance](##-Connecting-to-the-VM-Instance) we need to do some preparation.

1. First of all we need an SSH client, namely Putty
2. Head on over to https://www.putty.org/ and click on the **Download PuTTY** link
3. Scroll down to **Alternative binary files**
   1. click on **putty.exe** (64-bit x86)
   2. next scroll down and you'll find **puttygen** click on **puttygen.exe** (64-bit x86)
4. Open up **puttygen**
   1. Press **Generate**
   2. Copy the whole SSH key starting at ssh-rsa, we'll need this in the next section when [Creating the VM Instance](###-Creating-the-VM-instance)
   3. Press **Save public key** and save it to f.ex your Desktop
   4. Press **Save private key** and save it to f.ex your Desktop  
      It will ask about password protecting the key, this isn't necessary for this setup.

## Mac / Linux

Verify that we have a set of SSH key pairs

1. Open a terminal
2. Run the command `ls -l ~/.ssh/`.  
   If you see the files `id_rsa` and `id_rsa.pub`, you can continue on with [OCI (Oracle Cloud Infrastructure)](<##-OCI-(Oracle-Cloud-Infrastructure)>)
3. If you did not see these files, you can run the command `ssh-keygen -N '' -f ~/.ssh/id_rsa`
   Now you can re-run the command from step **2** and you should see both files.

# OCI (Oracle Cloud Infrastructure)

1. Head on over to https://cloud.oracle.com/ to sign up for a free account.  
   After logging in you will be shown a **Get Started** page.  
   All subsequent section starts from **Getting Started**.

## Creating the VM instance

1. From the [Home dashboard](https://cloud.oracle.com/home), scroll down a bit and click the **Create a VM instance**
2. Create compute instance
   1. Basic information
      1. Give the instance a name, for example `Valheim Server`
      2. Leave compartment default unless you already have another compartment set up that you'd like to use.
      3. Leave placement default.  
         **Note:** you might need to change it if it complains about placement allocation during deployment.
      4. Under **Image** click **Change image** and choose a **Canonical Ubuntu aarch64** image. Choose **Ubuntu 26.04** if it is available; otherwise choose the current OCI-supported **Ubuntu 24.04 aarch64** image and follow the 24.04 path described in [Ubuntu version](#ubuntu-version). Confirm with the **Select image** button.
         **Note:** select **aarch64** for an Ampere ARM server, and use the standard Ubuntu image rather than Minimal Ubuntu.
      5. Under **Shape** click **Change shape** and set the following:
         - Instance type: `Virtual machine`
         - Shape series: `Ampere`
         - Shape: `VM.Standard.A1.Flex`
      6. Expand the little triangle next to the shape name to set the following:
         - OCPUs: `4`
         - Memory: `24GB`
      7. Click **Select shape**
      8. Click **Next**
   2. Security
      1. Leave everything default
      2. Click **Next**
   3. Networking
      1. Select **Create new virtual cloud network** and leave the values as is.
      2. At the bottom you'll find **Add SSH keys**
         - For Linux and Mac you can find your SSH keys under `~/.ssh/id_rsa.pub`  
           In this case you can select **Upload public key files (.pub)** then navigate to `~/.ssh/id_rsa.pub`
         - For Windows, the SSH public key we copied in [Pre-requisite for Windows](###-Pre-requisite-for-Windows) can be pasted in by under **Paste public keys**
      3. Click **Next**
   4. Storage
      1. Leave everything default
      2. Click **Next**
   5. Review
      Here you'll get a final summary of what will be set up, review as needed, when ready, click **Create**.  
      This will take a couple of minutes while the instance is being provisioned / set up.  
      **Note**: If you get a warning about Out of Capacity, Go back to the **Placement** section under **Basic Information** and try another Domain (AD 1, AD 2 or AD 3), and try again.

      While we wait for it to be provisioned we'll go back to the dashboard and set up the networking.  
      Click on the **Cloud** header or [click here](https://cloud.oracle.com/) to go back to the Getting started page.

## Configuring the Network and firewall rules

1. At the top of the [Home dashboard](https://cloud.oracle.com/home), click on **Hamburger menu** in the top left corner
2. Under **Networking**, click **Virtual Cloud Networks**, then click the network (f.ex `vcn-20221120-1500`)
3. At the top under the network name, click on **Security**, then the `Default Security List for NETWORKNAME`
4. We will be creating a rule so that we can connect to the server from Valheim, click on **Security rules**.
   1. Under **Ingress Rules**, click **Add Ingress Rules**:
      - Source Type: `CIDR`
      - Source CIDR: `0.0.0.0/0`
      - IP Protocol: `UDP`
      - Source Port Range: `All` or leave blank
      - Destination Port Range `2456-2457`
5. Click on the **Hamburger menu** and navigate to **Compute**, then **Instances**
6. In the table next to the name of your instance, you'll see the Public IP. Copy this as we will need this in the next step.

# Connecting to the VM Instance

The IP Address we copied in the previous step will be referenced here as `IP_ADDRESS`

## Windows

1. Start **putty** which we downloaded in [Pre-requisite for Windows](###-Pre-requisite-for-Windows)
2. We'll configure the following parameters:
   - Host Name (or IP address): `IP_ADDRESS`
   - Port: `22`
   - Saved Sessions: `Valheim Server`
   - Close window on exit: `Never`
   - Click **Save**
3. Next in the navigation tree to the left go to **Connection** > **SSH** > **Auth** > **Credentials**
   1. Under **Private key file for authentication** click **Browse...** and navigate to the Private key we saved using **puttygen**
4. Go back up in the navigation tree to **Session** and click **Save**
5. Then click _Open_
6. You should within a couple of seconds see a prompt along the lines of `ubuntu@instance-20221120-1503:~$ `
7. You're now good to go to [Installing the Valheim Dedicated Server](#Installing-the-Valheim-Dedicated-Server)

## Mac / Linux

1. On Mac and Linux we already have an SSH client installed.
2. Open up a terminal then execute `ssh ubuntu@IP_ADDRESS`
3. You should within a couple of seconds see a prompt along the lines of `ubuntu@instance-20221120-1503:~$ `
4. You're now good to go to [Installing the Valheim Dedicated Server](#Installing-the-Valheim-Dedicated-Server)

# Installing the Valheim Dedicated Server

1. Run the following command:

   ```bash
   wget https://raw.githubusercontent.com/husjon/valheim_server_oci_setup/refs/heads/main/setup_valheim_server.sh
   ```

   This will download the installation script onto your server allowing it to set up everything which is needed.
   If you are using a fork, replace `husjon` with your GitHub username. When the script is run from a cloned checkout, its self-update logic detects the fork automatically.

2. Then run the following command:

   ```bash
   bash ./setup_valheim_server.sh
   ```

   The first time this is run, the setup script will update the operating system and then reboot.
   If you get notification about kernel upgrades, or restarting services you may just press `Enter`, allowing the default values be.
   After it's done you will be disconnected, wait about 15-20 seconds then reconnect to the server.

3. Run the same command again

   ```bash
   bash ./setup_valheim_server.sh
   ```

   **Note:** If you're playing on Console or Xbox Game Pass / Microsoft Game Pass, please enable Crossplay.  
   Also, read the [Crossplay](#crossplay-console--game-pass) section.

   The installation will take a couple of minutes to complete as the script installs all the necessary packages and set up the server with initial values.  
   Once it finishes it let you know that we need to make a small edit to one file then start the server.

# Configuring the Valheim Server

1. Open up the **server_credentials** file with `nano ~/server_credentials` (or text editor of choice)
2. Adjust **SERVER_NAME**, **WORLD_NAME**, **PASSWORD**, **PUBLIC**, and **CROSSPLAY** as you see fit.
   **Note**: The setup script populated the password field automatically with a random decently strong password.
   `CROSSPLAY=1` enables the cross-platform backend; `CROSSPLAY=0` uses the Steam backend. The generated launcher also exposes Valheim’s automatic save settings as `SAVE_INTERVAL`, `BACKUPS`, `BACKUP_SHORT`, and `BACKUP_LONG`.
3. When done, Press `Ctrl+X`, then `y` and finally `Enter`.  
   **Note**: Mac users might need to use the `Cmd` button instead of `Ctrl`

For further customization, you may want to change the `~/valheim_server/start_server.custom.sh` file.
Here you may add or remove flags and environment variables used by the server, for example when adding mods. The generated launcher uses an argument array so values containing spaces remain intact.

This file is only created if it does not exist, so re-running the setup script will leave it as it. Existing installations should move any custom copy aside, remove `~/valheim_server/start_server.custom.sh`, and re-run the setup script once to generate the Valheim 1.0 launcher with backup and crossplay support; reapply custom changes afterward.

# Starting the Valheim Server

To start the server, run the command `valheim_server start`  
This will take a couple of minutes as the world is being generated. Valheim 1.0 stores a world as a directory containing chunk files and metadata under `~/valheim_data/worlds_local`; do not treat a world as a single `.db` file anymore.

From within the game, it might not show in the **Select Server** list, instead click the **Add server** button and type in the address `IP_ADDRESS:2456` (Using the IP address from[Configuring the Network and firewall rules](###-Configuring-the-Network-and-firewall-rules))

More information can be found in the attached Readme.md file and can be viewed with `cat ~/Readme.md`

# Updating the Valheim Server

Whenever the Valheim client updates, the server also needs to be updated.  
To do this, log onto the VM then run the command `valheim_server update`.
This creates a complete `~/valheim_data` archive, stops the running server, and updates the server files.
Once done, you must start the server using `valheim_server start`

Before manually changing files or branches, create an additional backup with `valheim_server backup`. The helper stops the server briefly so the archive is consistent and stores it under `~/valheim_backups`.

# Crossplay (Console / Game Pass)

**Note**: Crossplay on ARM architecture is still dependent on the FEX emulation layer, so it remains experimental in this project. Valheim 1.0 itself supports crossplay between platforms.

Set `CROSSPLAY=1` in `~/server_credentials`; the generated launcher adds the `-crossplay` flag automatically. You can also add or remove the flag manually in `~/valheim_server/start_server.custom.sh` if you maintain a custom launcher.

This configures the server to allow for crossplay support. On this ARM setup it is experimental and might cause the server to crash; if that happens, set `CROSSPLAY=0` and restart the server.

After crossplay has been enabled, the join procedure is the same as normal using `IP:port`, however you can now also join by using a 6 digit code which can be found in the logs after the server has started (using the `valheim_server logs-live` command). Crossplay uses a relay backend and normally does not require Internet port forwarding; direct Steam-backend connections use UDP ports 2456-2457.
Example log message:  
`Session "My Valheim server" with join code 295265 and IP 12.34.56.78:2456 is active with 0 player(s)`

**Note:** Do keep in mind that the join code will change every time the server is restarted!

# Modding

FEX can execute the x86_64 server on ARM, but it does not make Valheim mods compatible. Valheim 1.0 changed the game and save format, so every mod and mod loader must explicitly support 1.0. BepInEx support on this ARM setup is not guaranteed; test mods against a backup and expect to remove them after updates.

If you want to experiment, edit `~/valheim_server/start_server.custom.sh` and install only versions that support the current Valheim server build. The project does not bundle a mod loader or promise mod compatibility. For background, see [BepInEx/BepInEx#336](https://github.com/BepInEx/BepInEx/issues/336) and the [Valheim 1.0 FAQ](https://www.valheimgame.com/support/valheim-1-0-faq/).

If you successfully run mods on an ARM instance, please share the details in the [Matrix space](#matrix).

As for a guide to install mods, here is one.  
https://www.youtube.com/watch?v=h2t9cSFidt0

# Installer Self-update

The `setup_valheim_server.sh` now has a self-update feature which allows it to update itself and apply bug fixes whenever the script is run. When launched from a Git checkout, it detects the GitHub `origin` remote and current branch, so a fork checks its own setup script instead of the upstream repository.

If you downloaded the script as a standalone file, set `SETUP_SCRIPT_URL` to the raw URL in your fork:

```bash
SETUP_SCRIPT_URL=https://raw.githubusercontent.com/YOUR_USER/valheim_server_oci_setup/refs/heads/main/setup_valheim_server.sh bash ~/setup_valheim_server.sh
```

An explicit `SETUP_SCRIPT_URL` always takes precedence over automatic detection.

After updating, it will show what have changed, update itself, then ask the user to restart the setup script.  
It is not retroactively applied, hence the script will need to be downloaded again f.ex with:

```bash
wget https://raw.githubusercontent.com/husjon/valheim_server_oci_setup/refs/heads/main/setup_valheim_server.sh -O ~/setup_valheim_server.sh
```

This will overwrite the existing script.

This feature was added **Thu, 15 Dec 2022 19:56:51 +0100**.

# Adding pre-existing worlds

Valheim 1.0 changed the on-disk world format. A current local world is a **directory** containing chunk files and metadata; copying only one file can produce an incomplete or new world. Always run `valheim_server backup` before importing or converting a world.

1. Make sure the world is stored locally rather than in Steam Cloud. In Valheim’s save manager, choose **Move to Local**, then exit Valheim cleanly.
2. Locate the local saves:
   - Windows: `%userprofile%/AppData/LocalLow/IronGate/Valheim/worlds_local`
   - Linux: `$HOME/.config/unity3d/IronGate/Valheim/worlds_local`
3. Stop the server with `valheim_server stop` and create a server backup with `valheim_server backup`.
4. For a **Valheim 1.0 world**, upload the entire world directory to `~/valheim_data/worlds_local/`. The directory name is the value to use for `WORLD_NAME`; do not rename or flatten the files inside it.
5. For a **pre-1.0 world**, upload the matching `.db` and `.fwl` files together directly into `~/valheim_data/worlds_local/`. Set `WORLD_NAME` to their shared basename. The first 1.0 launch will convert the legacy pair into the new folder format, so keep the backup until you have verified the result.
6. Start the server with `valheim_server start` and inspect `valheim_server logs-live` while it loads.

The server’s `-savedir` is set to `~/valheim_data`, so that directory—not the operating system’s default save location—is the one that matters for this installation. Valheim’s official [1.0 FAQ](https://www.valheimgame.com/support/valheim-1-0-faq/) confirms that existing saves remain available, while new content generates correctly only in unexplored areas.

# Installing a world from a .zip file

The repository includes `install_valheim_world.sh` for importing one world archive without manually moving save files. The importer validates the archive, rejects path traversal and symlinks, creates a full `valheim_server backup`, updates `WORLD_NAME`, and preserves the server’s running state.

Download it once on the server:

```bash
wget https://raw.githubusercontent.com/husjon/valheim_server_oci_setup/refs/heads/main/install_valheim_world.sh -O ~/install_valheim_world.sh
chmod +x ~/install_valheim_world.sh
```

Import a world by passing its zip file. The optional second argument overrides the world name:

```bash
~/install_valheim_world.sh ~/MyWorld.zip
~/install_valheim_world.sh ~/MyWorld.zip MyWorld
```

For Valheim 1.0, zip the complete world directory. The script also accepts an archive containing a matching legacy `.db` and `.fwl` pair. If a world with the same name already exists, add `--replace`; use `--no-start` to leave a server that was running before the import stopped:

```bash
~/install_valheim_world.sh --replace ~/MyWorld.zip
~/install_valheim_world.sh --no-start ~/MyWorld.zip MyWorld
```

The importer stores backups under `~/valheim_backups`. Keep the backup until the imported world has loaded successfully.

# Troubleshooting

In case you should experience any issues and would need some assistance, the install logs and server logs are helpful to troubleshoot the issue.

To help with this the following steps should be followed:

1. Create a log output of the running server using the following command:  
   `journalctl --no-pager --since=-1d --user -u valheim_server > ~/valheim_server.systemd.log`  
   This will take a snapshot of the logs from the Valheim Server from the last 24 hours.  
   In case the Valheim server was never started, this can be omitted.
2. Download the `install_valheim_server.log` and `valheim_server.systemd.log` file located under `/home/ubuntu` using f.ex [FileZilla](https://filezilla-project.org/download.php?type=client).  
   **Note:** Use port 22 for SFTP/SSH.
3. Go to https://gist.github.com/, click **Add File** for each file, then **Create Public / Secret Gist**  
   This creates a gist (similar to this guide) which we can go through to troubleshoot.
4. Copy the URL to the gist and create a comment down below describing the issue and adding the link to the gist.

I might be delayed due to work / timezones etc, but hoping to get you going as quickly as possible.

## Discord

I no longer deem Discord to be a safe space for anyone and I've disabled the invite link.  
Instead you may join the space on [Matrix](#matrix).

## Matrix

I've set up a space over on Matrix for support and feedback which you are welcome to join.  
https://matrix.to/#/!mdUorjAxVZJCpANCCh:matrix.org?via=matrix.org

### Joining Matrix

In case you're new to Matrix, you may do the following to create an account and join the space.

1. Click the invite link [Matrix](https://matrix.to/#/!mdUorjAxVZJCpANCCh:matrix.org?via=matrix.org)
2. Click **Continue** under the **Element** app (first option)
3. Click **Continue in your browser**
4. On the **Welcome to Element** page, press **Create Account**
   1. On the **Create account** page, press **Continue**
   2. Type in your username and press **Continue with email address**, unless you'd like to use any of the other providers.
   3. Fill in the form, providing your email address and set your password.
      A 6-digit code will be sent to your provided email address, type this in on the next page.
   4. You may choose to set a display name, press **Skip** if you want to just use your username
   5. On the **Continue to Element?** page, press **Continue**
   6. You should now be on the Home page of Element with a **Join** button for joining the **Setup Valheim OCI Server** space.
      If you don't see the Join button, just press the invite link in step 1.

# Changing versions

This could be useful in case the public version breaks something.
Run `valheim_server backup` before switching versions. After Valheim 1.0 converts a legacy world into the new folder format, an older branch may not be able to read it; keep the generated archive so you can restore the pre-conversion save if needed.

## Switcing to the Previous Stable Version

1. Run SteamCMD to change to the `default_old` branch

```bash
cd ~/steamcmd

./steamcmd.sh \
    +@sSteamCmdForcePlatformType linux \
    +force_install_dir "/home/$USER/valheim_server" \
    +login anonymous \
    +app_update 896660 -beta default_old validate \
    +quit
```

3. In Steam, right-click the game, open Properties, go to Betas and select `default_old` from the dropdown and wait for the game to update (this might take a few minutes).
4. Start the game and connect to your server as normal.

## Switching to the Public Beta Branch

1. Run SteamCMD to change to the `public-test` branch

```bash
cd ~/steamcmd

./steamcmd.sh \
    +@sSteamCmdForcePlatformType linux \
    +force_install_dir "/home/$USER/valheim_server" \
    +login anonymous \
    +app_update 896660 -beta public-test -betapassword yesimadebackups validate \
    +quit
```

3. In Steam, right-click the game, open Properties, go to Betas and select `public-test` from the dropdown and wait for the game to update (this might take a few minutes).  
   If `public-test` is not in the list, type in `yesimadebackups` in the Input field below and press **Check Code**.
4. Start the game and connect to your server as normal.

## Reverting back to the public version

1. Run SteamCMD to change to the `public` branch

```bash
cd ~/steamcmd

./steamcmd.sh \
    +@sSteamCmdForcePlatformType linux \
    +force_install_dir "/home/$USER/valheim_server" \
    +login anonymous \
    +app_update 896660 -beta public validate \
    +quit
```

3. In Steam, right-click the game, open Properties, go to Betas and select `None` from the dropdown and wait for the game to update (this might take a few minutes).
4. Start the game and connect to your server as normal.

# Oracle and Reclamation of Idle Compute Instances

Oracle have a policy on their Always Free instances whichs allows them to reclaim instances that are idle or using less than a certain percentile (See: [Always_Free_Resources](https://docs.oracle.com/en-us/iaas/Content/FreeTier/freetier_topic-Always_Free_Resources.htm#compute__idleinstances)).

For the most part using the server should not trigger this.

If the server should be flagged for reclaimation, you'll receive an email saying that it has been flagged for being idle for the last 7 days.  
Next it will say that if it continues for another 7 days, the server will be stopped.  
This gives us ample time to either back up the data or continue playing.

The only thing needed to do is to log onto your Oracle Cloid Infrastructure, go to your Instances and click the Restart button, this will pause the reclaimation.

# TODOs

- ~~Add ability to update the Valheim server prior to starting the server.~~  
  **Tue, 24 Jan 2023 23:01:18 +0100**  
  Now part of the `valheim_server` helper command.

- ~~Add information about adding pre-existing worlds~~  
  **Tue, 24 Jan 2023 22:47:19 +0100**

- ~~Add support for users other than `ubuntu`~~  
  **Tue, 24 Jan 2023 22:33:56 +0100**  
  Made it so that the install script no longer is tied to the `ubuntu` user.
