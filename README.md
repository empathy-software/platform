# platform

Jenkins job checkout for Empathy pipeline builds. One repo holds the pipeline, the shared compose template, the backup script, and the Ansible that deploys an app onto the test/build host or the production host.

The application being built is not in this repo. The pipeline clones it into `project/` from the job parameters.

`base-docker` is the host bootstrap (proxy, test machine, AWS). Jobs should not clone it.


## Layout

```text
Jenkinsfile              Test/build pipeline
Jenkinsfile.prod         Production pipeline
v2/Jenkinsfile           Newer test pipeline (releases, then deploy)
backup.pm                Save or restore DB dump and uploads via S3
env/docker-compose.yml.j2
infra/                   Playbooks, inventories, vault, Galaxy deps
  deploy.yml             Bring up the app stack on the test host
  deploy-prod.yml        Bring up the app stack on the production host
  deploy-restart.yml     Restart selected compose services
  deploy-site-secrets.yml
  deploy_vars.yml
  boot.yml               Provision a build host (Docker, certbot)
  playbook.yml           Local Vagrant path, not the Jenkins job
  encrypted              Ansible vault (AES256)
  requirements.yml       Galaxy pin: community.docker 5.3.0, geerlingguy roles
  collections/           community.docker, loaded from beside the playbooks
  roles/                 geerlingguy.docker and geerlingguy.certbot, used by boot.yml
  test/                  Inventory and vhost for the Jenkins test/build host
  prod/                  Inventory and vhost for the production host
```

Ansible's `playbook_dir` is `infra/` (the directory that contains `deploy.yml`). From there, `../env/` is this repo's compose template and `../project/` is the cloned app. That only works when this repo is the workspace root and `infra/` is this tree, not a second checkout dropped on top of it.


## What a test build does

`Jenkinsfile`, `Jenkinsfile.prod`, and `v2/Jenkinsfile` still have a "Clone infrastructure repo" stage that checks out `ssh://mikewhiting.co/var/git/org/infra` into `infra/`. That replaces the `infra/` directory in this repo for the rest of the job. Remove that stage once this repo is the job SCM, or the playbooks, vault, and inventories committed here are not the ones that run.

`Jenkinsfile` (and `v2/Jenkinsfile`):

1. Clones the app into `project/`.
2. Runs `ansible-playbook ../deploy.yml` from `infra/test`, with the vault password file.
3. Runs `ant` inside the `app-<id>` container, then `empathy` to set docroot, webroot, and database settings.
4. If `project/vendor` was missing at the start of the job, runs `empathy --mysql populate`. To force a fresh database, remove `project/vendor` before the build.

`Jenkinsfile.prod` runs `deploy-prod.yml` from `infra/prod`. Its inventory includes the `engywook` host. Restart uses `variable_host=engywook`. The test pipelines restart with `variable_host=control`.

`test/ansible.cfg` and `prod/ansible.cfg` set `vault_password_file` to `/var/jenkins_home/.vault_pass`. The test Jenkinsfile also passes the Jenkins credential `site-passfile` as `--vault-password-file`. Those two passwords must be the same, and must be the password for `infra/encrypted`. Rekey with `ansible-vault rekey infra/encrypted`, then update both password files. `ansible-playbook` does not read `requirements.yml`.


## Backups

`backup.pm` takes a project name, a URL, and `save` or `restore`. The pipeline runs it from the workspace root. Save dumps MySQL from the app container, archives `project/public_html/uploads`, and uploads a zip to `s3://mikejw.web-backup/<name>/` in `eu-west-1`. Restore downloads the latest object for that name, unpacks uploads and `dump.sql`, and runs `empathy --mysql populate`. The Jenkins agent needs AWS credentials that can read and write that bucket.


## Galaxy

`deploy.yml`, `deploy-prod.yml`, and `deploy-restart.yml` call `community.docker.docker_compose_v2`. Ansible loads `infra/collections/` before any copy installed on the agent, so the vendored tree must stay at the version named in `requirements.yml` (`community.docker` 5.3.0). Refresh it with:

```bash
ansible-galaxy collection install -r infra/requirements.yml --force
```

`boot.yml` applies `geerlingguy.docker` and `geerlingguy.certbot` from `infra/roles/`. The Jenkins deploy jobs do not run `boot.yml`.
