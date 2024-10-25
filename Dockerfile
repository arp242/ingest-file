FROM ubuntu:20.04
ENV DEBIAN_FRONTEND noninteractive

LABEL org.opencontainers.image.title    "FollowTheMoney File Ingestors"
LABEL org.opencontainers.image.licenses AGPL3
LABEL org.opencontainers.image.source   https://github.com/alephdata/ingest-file

# Use bash.
SHELL ["/bin/bash", "-c"]
ENV SHELL=/bin/bash

# Install packages.
COPY requirements.txt /tmp/
RUN <<EOF
	set -eu

	# List of packages to install.
	pkgs=(
		build-essential locales ca-certificates git

		# python deps (mostly to install their dependencies)
		python3-pip python3-dev python3-pil

		# tesseract
		tesseract-ocr libtesseract-dev libleptonica-dev pkg-config

		# libraries
		libxslt1-dev libpq-dev libldap2-dev libsasl2-dev zlib1g-dev libicu-dev
		libxml2-dev

		# package tools
		unrar p7zip-full

		# audio & video metadata
		libmediainfo-dev

		# image processing, djvu
		imagemagick-common imagemagick mdbtools djvulibre-bin libtiff5-dev
		libjpeg-dev libfreetype6-dev libwebp-dev libtiff-tools ghostscript
		librsvg2-bin jbig2dec pst-utils

		# PDF convert: libreoffice + a bunch of fonts
		libreoffice fonts-opensymbol hyphen-fr hyphen-de hyphen-en-us hyphen-it
		hyphen-ru fonts-dejavu fonts-dejavu-core fonts-dejavu-extra
		fonts-droid-fallback fonts-dustin fonts-f500 fonts-fanwood
		fonts-freefont-ttf fonts-liberation fonts-lmodern fonts-lyx
		fonts-sil-gentium fonts-texgyre fonts-tlwg-purisa
	)
	# Add tesseract languages.
	langs=(eng swa swe fil tur ukr nld nor pol por ron rus slk slv spa sqi srp
		ind isl ita kan kat khm  lav lit mkd mya mlt msa est fin fra frk heb hin
		hrv hye hun bul cat ces nep dan deu ell afr ara aze bel uzb
		# tam tel tha vie spa_old ita_old jpn kor mal eus frm glg grc ben
		# chi_sim chi_tra chr enm epo equ
	)
	for l in ${langs[@]}; do
		pkgs+=(tesseract-ocr-$l)
	done

	# Install and clean.
	apt-get -qq -y update
	apt-get -qq -y install ${pkgs[@]}
	apt-get -qq -y autoremove
	apt-get clean
	rm -rf /var/lib/apt/lists/* /tmp/* /var/tmp/*

	# Generate en-US locale.
	localedef -i en_US -c -f UTF-8 -A /usr/share/locale/locale.alias en_US.UTF-8

	# Download the ftm-typepredict model
	mkdir -p /models
	curl -o /models/model_type_prediction.ftz https://public.data.occrp.org/develop/models/types/type-08012020-7a69d1b.ftz

	# Setup user.
	groupadd -g 1000 -r app
	useradd -m -u 1000 -s /bin/false -g app app

	# Install dependencies.
	pip3 install --no-cache-dir --prefer-binary --upgrade pip
	pip3 install --no-cache-dir --prefer-binary --upgrade setuptools wheel
	pip3 install --no-cache-dir --no-binary tesserocr -r /tmp/requirements.txt

	# Install spaCy models
	python3 -m spacy download en_core_web_sm
	# python3 -m spacy download zh_core_web_sm
	for l in da de el es fr it lt mk nb nl pl pt ro ru; do
		python3 -m spacy download $l_core_news_sm
	done
EOF

# Set up the locale and make sure the system uses unicode for the file system.
ENV LANG='en_US.UTF-8' \
    TZ='UTC' \
    OMP_THREAD_LIMIT='1' \
    OPENBLAS_NUM_THREADS='1'

COPY . /ingestors
WORKDIR /ingestors
RUN <<EOF
	set -eu
	pip3 install --no-cache-dir --config-settings editable_mode=compat --use-pep517 -e /ingestors
	chown -R app:app /ingestors
EOF

ENV ARCHIVE_TYPE=file \
    ARCHIVE_PATH=/data \
    FTM_STORE_URI=postgresql://aleph:aleph@postgres/aleph \
    REDIS_URL=redis://redis:6379/0 \
    TESSDATA_PREFIX=/usr/share/tesseract-ocr/4.00/tessdata \
    LD_PRELOAD=/usr/lib/aarch64-linux-gnu/libgomp.so.1

# USER app
CMD ingestors process
