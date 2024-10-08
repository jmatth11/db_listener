# DB listener

Sets up listeners on all tables in a postgres database to be notified of insert/update/delete.

The program tears down listeners once brought down.

You can use this info to display new or updated entries happening to your database in real time as a kind of local monitoring system.

This was driven by the desire to debug DB changes easier for local development.


This program also spins up a small server that allows for a websocket connection to get updates on the DB notifications.

## Demo

https://github.com/user-attachments/assets/e6ab4dd6-138d-4afb-b002-115766010c2f
