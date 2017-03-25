#!/bin/bash

[[ "$(curl -Is http://127.0.0.1 | head -n 1|cut -d$' ' -f2)" == "200" ]]