#!/usr/bin/env bash

cp -R _common/* ./get/
cp -R _common/* ./go/
cp -R _common/* ./connect/
cp -R _common/* ./checkin/

node generateGo.mjs
