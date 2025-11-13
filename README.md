# DB listener

Sets up listeners on all tables in a postgres database to be notified of insert/update/delete.

The program tears down listeners once brought down.

You can use this info to display new or updated entries happening to your database in real time as a kind of local monitoring system.

This was driven by the desire to debug DB changes easier for local development.


This program also spins up a small server that allows for a websocket connection to get updates on the DB notifications. You can find a default implementation [here](https://github.com/jmatth11/db_listener_web)

## Run with docker.

Open both of these files to view what build/environment args you can add to fit
your needs. A list of args are shown in comments within the files.

### Build

Use the `docker_build.sh` file to build the `db-listener` docker image.

### Run

Use the `docker_run.sh` file to run the `db-listener` docker image.

By default it runs with network mode set to `host` so the image can connect to
the postgres DB on the host machine.

It will also pull the simple db-listener web project and host it on port `3000`
by default. This can be changed in the `docker_build.sh` file with flags.

## Demo

https://github.com/user-attachments/assets/e6ab4dd6-138d-4afb-b002-115766010c2f
