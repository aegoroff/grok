FROM ubuntu:20.04

ENV TZ=Europe/Moscow
RUN ln -snf /usr/share/zoneinfo/$TZ /etc/localtime && echo $TZ > /etc/timezone

RUN apt-get update && DEBIAN_FRONTEND=noninteractive apt-get install -y  --no-install-recommends \
    build-essential \
    gdb             \
    git             \
    pkg-config      \
    zip             \
    unzip           \
    ninja-build     \
    cmake           \
    lcov            \
    graphviz        \
    doxygen         \
    openssl         \
    wget            \
    curl            \
    ca-certificates \
    apache2-dev     \
    libapr1-dev     \
    libaprutil1-dev \
    flex            \
    bison           \
    sqlite3         
    
# Cleanup
RUN  apt-get clean && \
  rm -rf /var/lib/apt
  
