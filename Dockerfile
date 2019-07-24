FROM php:7.2-apache

ENV DOWNLOAD_URL https://www.limesurvey.org/stable-release?download=2595:limesurvey3178%20190722targz
ENV DOWNLOAD_SHA256 11b1bc01aeee59afc54267873c144bb6370b56c0b3e8f3ab0ba0cd78db470a76

# install the PHP extensions we need
RUN apt-get update && apt-get install -y libc-client-dev libfreetype6-dev libmcrypt-dev libpng-dev libjpeg-dev libldap2-dev zlib1g-dev libkrb5-dev libtidy-dev libzip-dev libsodium-dev && rm -rf /var/lib/apt/lists/* \
	&& docker-php-ext-configure gd --with-freetype-dir=/usr/include/  --with-png-dir=/usr --with-jpeg-dir=/usr \
	&& docker-php-ext-install gd mysqli pdo pdo_mysql opcache zip iconv tidy \
    && docker-php-ext-configure ldap --with-libdir=lib/x86_64-linux-gnu/ \
    && docker-php-ext-install ldap \
    && docker-php-ext-configure imap --with-imap-ssl --with-kerberos \
    && docker-php-ext-install imap \
    && docker-php-ext-install sodium \
    && pecl install mcrypt-1.0.1 \
    && docker-php-ext-enable mcrypt

RUN a2enmod rewrite

# set recommended PHP.ini settings
# see https://secure.php.net/manual/en/opcache.installation.php
RUN { \
		echo 'opcache.memory_consumption=128'; \
		echo 'opcache.interned_strings_buffer=8'; \
		echo 'opcache.max_accelerated_files=4000'; \
		echo 'opcache.revalidate_freq=2'; \
		echo 'opcache.fast_shutdown=1'; \
		echo 'opcache.enable_cli=1'; \
	} > /usr/local/etc/php/conf.d/opcache-recommended.ini

RUN set -x; \
	curl -SL "$DOWNLOAD_URL" -o /tmp/lime.tar.gz; \
    echo "$DOWNLOAD_SHA256 /tmp/lime.tar.gz" | sha256sum -c -; \
    tar xf /tmp/lime.tar.gz --strip-components=1 -C /var/www/html; \
    rm /tmp/lime.tar.gz; \
    chown -R www-data:www-data /var/www/html

#Set PHP defaults for Limesurvey (allow bigger uploads)
RUN { \
		echo 'memory_limit=256M'; \
		echo 'upload_max_filesize=128M'; \
		echo 'post_max_size=128M'; \
		echo 'max_execution_time=120'; \
        echo 'max_input_vars=10000'; \
        echo 'date.timezone=UTC'; \
	} > /usr/local/etc/php/conf.d/uploads.ini

VOLUME ["/var/www/html/plugins"]
VOLUME ["/var/www/html/upload"]

COPY docker-entrypoint.sh /usr/local/bin/
RUN ln -s usr/local/bin/docker-entrypoint.sh /entrypoint.sh # backwards compat

## add msmtp software as method to send emails
## taken from https://github.com/fjudith/docker-limesurvey/blob/master/Dockerfile
RUN apt-get update && apt-get install -yqqf --no-install-recommends msmtp crudini
RUN pear install Net_SMTP
RUN touch /etc/msmtprc && \
    mkdir -p /var/log/msmtp && \
    chown -R www-data:adm /var/log/msmtp && \
    touch /etc/logrotate.d/msmtp && \
    rm /etc/logrotate.d/msmtp && \
    echo "/var/log/msmtp/*.log {\n rotate 12\n monthly\n compress\n missingok\n notifempty\n }" > /etc/logrotate.d/msmtp && \
    crudini --set /usr/local/etc/php/conf.d/msmtp.ini "mail function" "sendmail_path" "'/usr/bin/msmtp -t'" && \
    touch /usr/local/etc/php/php.ini && \
    crudini --set /usr/local/etc/php/php.ini "mail function" "sendmail_path" "'/usr/bin/msmtp -t'"

# ENTRYPOINT resets CMD
ENTRYPOINT ["docker-entrypoint.sh"]
CMD ["apache2-foreground"]
