# VVV Custom Site Provisioner

Based on the [default VVV Site Provisioner](https://github.com/Varying-Vagrant-Vagrants/custom-site-template)

* Installs Wordpress as a dependency in a `wp` directory
* Assumes content directory is called `content`
* Leverages `composer` for installing Wordpress, Plugins and external libraries
* Wraps around an existing site using a `tmp` directory.
* Prepares site for deployment using Git Actions