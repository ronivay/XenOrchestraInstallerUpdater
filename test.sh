#!/bin/bash

if [[ -n $(command -v git) ]]; then
    echo "jep"
else
    echo "noup"
fi
