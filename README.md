Set up new VPS:

* configure setup script'
  * replace/adapt users
  * customize 'login slack notify' block (text and webhook url)
* copy script to new VPS instance
* run script
* copy users .ssh/authorized_keys as needed
* configure external job to download monthly backup archive
* create application deployments (see my other repositories for examples)
