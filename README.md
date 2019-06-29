# e2e container

This repository holds the build scripts of SkyWalking e2e docker container . 

## Ports

The container exposes port 8080 11800 and 12800 to make the Web App and OAP accessible outside,
as well as some port (9090 9091 9092 9093 and 9094) that can be used by instrumented services,
if your instrumented services need to be accessible out of the container, make sure to use those ports.

Here are some environment variables that can be customized to control the behaviours of the container.

## Environment Variables

- `SW_HOME`

The home directory of SkyWalking that you can mount the host directory to, under which the directory structures
should be the same as what the distribution package look like, meaning `ls $SW_HOME` should produce something like:

```shell
$ ls $SW_HOME
total 136
-rw-r--r--    1 kezhenxu94  admin  28526 Jun 19 20:13 LICENSE
-rw-r--r--    1 kezhenxu94  admin  31850 Jun 16 08:19 NOTICE
-rw-r--r--    1 kezhenxu94  admin   1978 May 12 22:09 README.txt
drwxr-xr-x    8 kezhenxu94  admin    272 Jun 16 15:58 agent
drwxr-xr-x   12 kezhenxu94  admin    408 Jun 25 22:41 bin
drwxr-xr-x    8 kezhenxu94  admin    272 Jun 25 22:40 config
drwxr-xr-x    3 kezhenxu94  admin    102 Jun 28 23:01 e2e-samples-1.0.0.jar
-rw-r--r--    1 kezhenxu94  admin    728 Jun 28 21:21 index.html
drwxr-xr-x   36 kezhenxu94  admin   1224 Jun 19 20:13 licenses
drwxr-xr-x    6 kezhenxu94  admin    204 Jun 28 21:16 logs
drwxr-xr-x  199 kezhenxu94  admin   6766 Jun 19 23:58 oap-libs
drwxr-xr-x    4 kezhenxu94  admin    136 Jun 25 22:40 webapp
```

- `SERVICE_HOME` and `INSTRUMENTED_SERVICE`

`SERVICE_HOME` is the home directory of the instrumented services, and `INSTRUMENTED_SERVICE` is the
instrumented service jar file name, you may typically want to mount the directory where your jar locates 
and set it as `SERVICE_HOME`, and set `INSTRUMENTED_SERVICE` to your jar file name.

Starting multiple service jars are also supported, just put all the jars into `SERVICE_HOME` and set
`INSTRUMENTED_SERVICE_1`, `INSTRUMENTED_SERVICE_2` `INSTRUMENTED_SERVICE_n` to your jar file names that
you want to start.

- `AGENT_HOME`

`AGENT_HOME` is the home directory of the SkyWalking agent, it's the same hierarchy of the agent directory
in the distribution package.

```shell
total 34960
drwxr-xr-x   7 kezhenxu94  admin       238 Jun 16 15:58 activations
drwxr-xr-x   3 kezhenxu94  admin       102 Jun 16 15:58 config
drwxr-xr-x   3 kezhenxu94  admin       102 Jun 25 22:47 logs
drwxr-xr-x   9 kezhenxu94  admin       306 Jun 16 15:59 optional-plugins
drwxr-xr-x  61 kezhenxu94  admin      2074 Jun 23 21:11 plugins
-rw-r--r--   1 kezhenxu94  admin  17895882 Jun 23 21:11 skywalking-agent.jar
``` 
