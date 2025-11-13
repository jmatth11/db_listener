#!/usr/bin/env bash

# running in network host mode to access postgres DB on machine.
sudo docker run --network=host db-listener

# Add these environment args to suit your needs.
# -e PG_HOST=<host IP>
# -e PG_PORT=<port>
# -e PG_USERNAME=<db username>
# -e PG_PASSWORD=<db password>
# -e PG_DATABASE=<db name>
# -e SERVER_HOST=<web server host IP>
# -e SERVER_PORT=<web server port>
