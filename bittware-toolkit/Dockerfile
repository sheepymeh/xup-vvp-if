FROM ubuntu:16.04
ENV DEBIAN_FRONTEND=noninteractive
COPY bw2tk-lite-2018.6.u1604.amd64.deb /tmp/

RUN dpkg-deb -x /tmp/bw2tk-lite-2018.6.u1604.amd64.deb / && \
	rm -f /tmp/bw2tk-lite-2018.6.u1604.amd64.deb && \
	rm -rf /var/lib/apt/lists/*

ENV BWTK=/opt/bwtk/2018.6L
ENV PATH="${BWTK}/bin:${PATH}"
ENV LD_LIBRARY_PATH="${BWTK}/lib:${LD_LIBRARY_PATH}"

WORKDIR /root
CMD ["/bin/bash"]
