## Tests

Automated tests to run installation on different operating systems and make sure the login page replies correctly.

`run-tests.sh` without arguments builds up each vagrant box one by one and outputs if curl check was successful or not.

```
./run-tests-all.sh
CentOS HTTP Check: success
Debian HTTP Check: success
Ubuntu HTTP Check: success
```

Single OS can be tested by giving Ubuntu, CentOS or Debian as first argument for the script.

```
./run-tests.sh Ubuntu
Ubuntu HTTP Check: success
```

Requirements:
```
OSX (not tested with anything else since this is mainly for my own use)
Vagrant
Virtualbox
````
