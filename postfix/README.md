### Use

Clone the repository.

```sh
$ git clone https://github.com/EasyEngine/dockerfiles.git
```

Build Docker container

```sh
$ cd postfix
$ docker build . -t easyengine/postfix
```

Enter in the docker shell.

```sh
$ docker run -dit --rm --name postfix easyengine/postfix bash
```

Send mail using mail command
```sh
# echo "This is a test mail." | mail -s "This is subject" mail@xample.com
```