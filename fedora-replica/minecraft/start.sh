#!/bin/bash

cd /home/minecraft/server

java -Xmx18g -Xms512M -Xloggc:log.txt -jar server.jar nogui
