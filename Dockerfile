FROM rocker/tidyverse:4.2.3
MAINTAINER a.chroni@stjude.org
WORKDIR /rocker-build/

# https://packagemanager.rstudio.com/cran/2024-04-24
# https://packagemanager.rstudio.com/cran/latest
RUN RSPM="https://packagemanager.rstudio.com/cran/2024-04-24" \
  && echo "options(repos = c(CRAN='$RSPM'), download.file.method = 'libcurl')" >> /usr/local/lib/R/etc/Rprofile.site
  
  
  
COPY scripts/install_bioc.r .
COPY scripts/install_github.r .

### Install apt-getable packages to start
#########################################
RUN apt-get update && \
    apt-get install -y --no-install-recommends apt-utils dialog

# Add curl, bzip2 and some dev libs
RUN apt-get update -qq && apt-get -y --no-install-recommends install \
    curl \
    bzip2 \
    zlib1g \
    libbz2-dev \
    liblzma-dev \
    libreadline-dev

# libmagick++-dev is needed for coloblindr to install
RUN apt-get -y --no-install-recommends install \
    libgdal-dev \
    libudunits2-dev \
    libmagick++-dev
   
# cmakeis needed for ggpubr to install
RUN apt-get -y --no-install-recommends install \
    cmake

# install R packages from GitHub
# scooter 
RUN ./install_github.r 'igordot/scooter' --ref '2a639459d3848e111717624497797441cfbf1747' 

# install Seurat-related packges
RUN apt-get update -qq && \
    R -e "install.packages('remotes', repos='http://cran.r-project.org')"

RUN apt-get update -qq && \
    R -e "remotes::install_github('satijalab/seurat-wrappers@community-vignette', force = TRUE)" 

# Set the CRAN mirror to RStudio's
ENV R_CRAN_MIRROR=https://cran.rstudio.com/

# Set the RStudio Package Manager CRAN repository
# ENV R_PACKAGEMANAGER=https://packagemanager.rstudio.com/cran/latest


# Install system dependencies
RUN apt-get update && apt-get install -y \
    libcurl4-openssl-dev \
    libssl-dev \
    libxml2-dev \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/*
    
RUN R -e "remotes::install_version('Seurat', '4.4.0', repos=c('${R_CRAN_MIRROR}', 'https://satijalab.r-universe.dev', getOption('repos')))"
# RUN R -e "remotes::install_version('Seurat', '4.4.0', repos=c('${R_PACKAGEMANAGER}', 'https://satijalab.r-universe.dev', getOption('repos')))"

# install R packages from CRAN
RUN install2.r \
    celldex \
    clustree \
    cowplot \
    data.table \
    devtools \
    flexmix \
    flextable \
    forcats \
    fs \
    future \
    GGally \
    ggh4x \
    ggplot2 \
    ggpmisc \
    ggrepel \
    ggthemes \
    grid \
    harmony \
    igraph \
    irlba \
    knitr \
    leiden \
    optparse \
    patchwork \
    purrr \
    RColorBrewer \
    RcppPlanc \
    reshape2 \
    rliger \
    rlist \  
    R.utils \
    SeuratObject \
    SingleR \
    shiny \
    SoupX \
    stringr \
    tidytext \
    tidyverse \
    tinytex \
    yaml

# install R packages from BiocManager
# RUN ./install_bioc.r \
#  miQC
  
# Install BiocManager
RUN R -e "install.packages('BiocManager')"

# Set Bioconductor repository and install packages
RUN R -e "options(repos = BiocManager::repositories()); \
           BiocManager::install(c('miQC', 'scater', 'scDblFinder', 'SingleCellExperiment'))"  

# Install pip3 and low-level python installation reqs
RUN apt-get update

RUN apt-get -y --no-install-recommends install \
    python3-pip  python3-dev

RUN ln -s /usr/bin/python3 /usr/bin/python    

RUN pip3 install \
    "leidenalg" 

WORKDIR /rocker-build/

ADD Dockerfile .
