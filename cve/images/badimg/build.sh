#!/usr/bin/env bash
docker build -t localhost:5000/badimg:latest $(dirname $0)
docker push localhost:5000/badimg:latest
