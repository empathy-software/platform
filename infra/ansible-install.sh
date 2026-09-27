#!/bin/bash

ansible-galaxy role install -r requirements.yml --roles-path ./roles
ansible-galaxy collection install -r requirements.yml -p ./collections


