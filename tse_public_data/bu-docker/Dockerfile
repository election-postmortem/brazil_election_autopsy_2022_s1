FROM python:latest

RUN apt-get update

RUN apt-get -yq install python3-pip tree

RUN pip install asn1tools asn1crypto ed25519 ecdsa

RUN git clone https://github.com/cslashm/ECPy.git && cd ECPy && pip install .

WORKDIR /bu

ADD docker-files/spec ./spec
ADD docker-files/python ./python
ADD docker-files/bin ./bin

RUN mkdir /bu-files

VOLUME /bu-files

RUN tree /bu

ENTRYPOINT ["/bu/bin/entrypoint.sh"]
