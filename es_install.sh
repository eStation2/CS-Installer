#!/bin/bash

target="estation"
down=0

# Check if any arguments were provided
if [ $# -eq 0 ]; then
  echo "No arguments provided."
fi

# Iterate over the arguments
for arg in "$@"; do
  # Check if the current argument has the value "down"
  if [ "$arg" == "down" ]; then
    down=1
  fi
done

if [ $down == 1 ]; then
  ./cs_install.sh down
else
  all_args="$@ -t $target"
  ./cs_install.sh $all_args
fi

