FROM ubuntu:24.04

ENV DEBIAN_FRONTEND=noninteractive
ENV HOME=/root

RUN apt-get update && apt-get install -y \
    openssh-server git curl ca-certificates tini rsync \
    && rm -rf /var/lib/apt/lists/*

# chisel — the websocket tunnel
RUN curl -L https://github.com/jpillora/chisel/releases/latest/download/chisel_linux_amd64.gz \
    | gunzip > /usr/local/bin/chisel && chmod +x /usr/local/bin/chisel

# Set root password to "root" and enable password auth
RUN echo "root:root" | chpasswd \
    && sed -i 's/#PermitRootLogin prohibit-password/PermitRootLogin yes/' /etc/ssh/sshd_config \
    && sed -i 's/#PasswordAuthentication yes/PasswordAuthentication yes/' /etc/ssh/sshd_config \
    && sed -i 's/UsePAM yes/UsePAM no/' /etc/ssh/sshd_config

COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

EXPOSE 8080

ENTRYPOINT ["/usr/bin/tini", "--", "/entrypoint.sh"]
