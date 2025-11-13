#!/usr/bin/env bash

sudo docker build -t db-listener .
# add this argument to change the exposed port.
# --build-arg SERVER_PORT=<port>
