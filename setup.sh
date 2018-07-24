#!/usr/bin/env bash


echo "indicator-multiload:  ppa,update,install ..."
sudo add-apt-repository ppa:indicator-multiload/stable-daily
sudo apt-get update
sudo apt-get install indicator-multiload


