

def basePath = ""
def repo = ""
def buildString = ""
def branchId = ""
def url = ""
def branch = ""
def jobName = env.JOB_NAME
def jobBaseName = "${jobName}".split('/').last()
def backup = ""
def restore = ""
def subRepo = ""
def subRepoRepo = ""
def subRepoBranch = ""
def initDB = false
def noWWW = false
def liveURL = ""
def liveURL2 = ""
def restart = "'[]'"
def rebuild = "'[]'"
def appContainer = "v8"
def workspace = ""


if (params.appContainer != null) {
    appContainer = params.appContainer
}

if (params.restartContainers != null) {
    def content = params.restartContainers.readLines().collect{"\\\"${it}\\\""}.join(', ');
    restart = "'[${ content }]'"
}
if (params.rebuildContainers != null) {
    def content = params.rebuildContainers.readLines().collect{"\\\"${it}\\\""}.join(', ');
    rebuild = "'[${ content }]'"
}

if (params.branch != null) {
    branch = params.branch
}

if (params.repo != null) {
    repo = params.repo
}

if (params.url != null) {
    url = params.url
}

if (params.buildString != null) {
    buildString = params.buildString
}

if (params.backup != null) {
    backup = params.backup
}

if (params.restore != null) {
    restore = params.restore
}

if (params.subRepo != null) {
     subRepo = params.subRepo
}

if (params.subRepoRepo != null) {
    subRepoRepo = params.subRepoRepo
}

if (params.subRepoBranch != null) {
    subRepoBranch = params.subRepoBranch
}

if (params.noWWW != null) {
    noWWW = params.noWWW
}

def repoUrl = (repo ==~ /^(https?:\/\/|git@|ssh:\/\/).*/) ? repo : "ssh://mikewhiting.co/var/git/${repo}"

pipeline {
    agent any
    environment {
        ENVIRONMENT = 'test'
    }
    stages {
       stage("Assign workspace") {
            steps {
                script {
                    workspace = pwd()
                    echo "${workspace}"
                }

            }
        }
        stage("determine www") {
            steps {
                script {
                    if (!noWWW) {
                        liveURL = "www.${url}"
                        liveURL2 = "${url}"
                    } else {
                        liveURL = "${url}"
                        liveURL2 = ""
                    }
                }
            }
        }
        stage("Echo restart") {
            steps {
                echo restart
            }
        }
        stage("Echo live url") {
            steps {
                echo "${liveURL}"
            }
        }
        stage("Echo path") {
            steps {
                echo "${basePath}"
            }
        }
        stage("BB build started") {
            steps {
                // get base path
                script {
                    basePath = sh (
                        script: "pwd",
                        returnStdout: true
                    ).trim()
                }
                // get branch id
                script {
                    branchId = sh (
                        script: 'printf %s ' + url + ' | md5sum | awk \'{print $1}\'',
                        returnStdout: true
                    ).trim()
                }
            }
        }
        stage("Determine initDB") {
            steps {
                script {
                    if (!fileExists("${basePath}/project/vendor")) {
                        initDB = true;
                    }
                }
            }
        }
        stage("Echo initDB") {
            steps {
                echo "${initDB}"
            }
        }
        stage("Clone infrastructure repo") {
            steps {
                dir("${basePath}/infra") {
                    git (
         	            credentialsId: 'git',
                        url: "ssh://mikewhiting.co/var/git/org/infra",
                        branch: "master"
                    )
                }
            }
        }
        stage("Main build") {
            steps {
                dir("${basePath}/project") {
                    git (
		                credentialsId: 'git',
                        url: repoUrl,
                        branch: branch
                    )
                }
            }
        }
	    stage("Sub Repo") {
            when {
                allOf {
                    expression { subRepo == true }
                }
            }
            steps {
                dir("${basePath}/project/sub") {
                    git (
                        credentialsId: 'git',
                        url: "ssh://mikewhiting.co/var/git/" + subRepoRepo,
                        branch: subRepoBranch
                    )
                }
            }
        }
        stage("Backup") {
            when {
                allOf {
                    expression { backup == true }
                }
            }
            steps {
                dir("${basePath}") {				
                    sh "perl ./backup.pm ${jobBaseName} ${url} save"
                }
            }
        }
        stage("Restore") {
            when {
                allOf {
                    expression { restore == true }
                }
            }
            steps {
                dir("${basePath}") {
                    sh "perl ./backup.pm ${jobBaseName} ${url} restore"
                }
            }
        }
        stage("Deploy to 'test' without using branch id") {
            when {
                allOf {
                    expression { backup == false }
                    expression { restore == false }
                }
            }
            steps {            
                dir("${basePath}/infra/test") {
                    script {
                        def parsedRebuild
                        if (rebuild?.trim()) {
                            try {
                                // If rebuild is something like '["go"]', parse it into a real List
                                parsedRebuild = new groovy.json.JsonSlurperClassic().parseText(rebuild)
                            } catch (Exception e) {
                                // Fallback for safety — treat any garbage as empty
                                parsedRebuild = []
                            }
                        } else {
                            parsedRebuild = []
                        }

                        def extra = [
                          app_container: appContainer ?: '',
                          url:          liveURL ?: '',
                          url2:         liveURL2 ?: '',
                          branch_type:  '',
                          build_type:   '',
                          branch_id:    branchId ?: '',
                          rebuild:      parsedRebuild,   // ✅ A real list here
                          workspace:    workspace
                        ]

                        writeFile file: 'extra_vars.json',
                            text: groovy.json.JsonOutput.toJson(extra)
                    }
                    withCredentials([file(credentialsId: 'site-passfile', variable: 'VAULT_PASS_FILE')]) {
                        sh '''
                            set -eu
                            chmod 400 "$VAULT_PASS_FILE"
                            ansible-playbook ../deploy.yml \
                              --extra-vars @extra_vars.json \
                              --vault-password-file "$VAULT_PASS_FILE"
                        '''
                    }
                }
            }
        }
        stage("Compile simple") {
            when {
                allOf {
                    expression { backup == false }
                    expression { restore == false }
                    expression { buildString.isEmpty() }
                }
            }
            steps {
                sh "docker exec -u www-data app-${branchId} ant"
            }
        }
        stage("Compile param") {
            when {
                allOf {
                    expression { backup == false }
                    expression { restore == false }
                    expression { !buildString.isEmpty() }
                }
            }
            steps {
                sh "docker exec -u www-data app-${branchId} ant -DbuildString ${buildString}"
            }
        }
        stage("restart containers") {
            when {
                allOf {
                    expression { restart != "[]" }
                    expression { restart != "'[]'" }
                    expression { backup == false }
                    expression { restore == false }
                }
            }
            steps {
                dir("${basePath}/infra/test") {
                    sh "ENVIRONMENT=test ansible-playbook ../deploy-restart.yml -e \"workspace=${workspace} variable_host=control branch_type= build_type= restart=${restart}\""
                }
            }
        }
        stage("Configure") {
            steps {
                sh "docker exec -u www-data app-${branchId} php ./vendor/bin/empathy --set_docroot /var/www/project"
                sh "docker exec -u www-data app-${branchId} php ./vendor/bin/empathy --set_webroot ${liveURL}"
                sh "docker exec -u www-data app-${branchId} php ./vendor/bin/empathy --set_publicdir \"\""
                sh "docker exec -u www-data app-${branchId} php ./vendor/bin/empathy --misc tpl_cache"
                sh "docker exec -u www-data app-${branchId} php ./vendor/bin/empathy --set_dbserver mysql"
                sh "docker exec -u www-data app-${branchId} php ./vendor/bin/empathy --set_dbuser root"
                sh "docker exec -u www-data app-${branchId} php ./vendor/bin/empathy --set_dbpass example"
            }
        }
        stage("init db data") {
            when {
                allOf {
                    expression { initDB == true }
                }
            }
            steps {
                sh "docker exec -u www-data app-${branchId} php ./vendor/bin/empathy --mysql populate"
            }
        }
    }
}
