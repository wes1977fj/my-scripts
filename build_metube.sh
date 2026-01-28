$ curl -sL https://your-script-url/build_metube.sh | sudo bash

Running installer for user: dietpi (UID: 1000, GID: 1000)
Starting metube interactive deployment...
Checking dependencies...
Creating directories...
Writing docker-compose.yml...
Building container from /docker/metube...

The default Docker network is 'bridge'. Use a different one? (y/n): n
Using network: bridge

[+] Running 2/2
 ⠿ Network metube_default  Created                                       0.1s
 ⠿ Container metube        Started                                       0.9s

Configure Samba shares? (y/n): y

Which directory would you like to share?
  1) /docker
  2) /media
  3) /media/ytdl
  c) Custom path
  n) None / Done
Select an option: 2
[0;32mAdded '/media' to the list.[0m

Share another directory?
  1) /docker
  2) /media
  3) /media/ytdl
  c) Custom path
  n) Done
Select an option: n

--- Confirmation ---
The following shares are ready:
  1) /media
Action: (p)roceed, (r)emove, (c)ancel: p
Proceeding with installation...
Adding share '[media]'...
Restarting Samba service...
[0;32mSamba configuration complete.[0m

[0;32m--------------------[0m
[0;32mInstallation Complete![0m

[0;32mDeployment successful![0m
[0;32mAccess MeTube at http://192.168.1.100:5009[0m
[0;32m--------------------[0m
$
