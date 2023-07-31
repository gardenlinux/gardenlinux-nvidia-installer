@Library(['piper-lib', 'piper-lib-os']) _
@Library(["AIF_CICD_Toolkit@master"])

def xmake
def git
def wsDockerScanConfig
def wsDockerProductToken
def wsScanIncludingBaseImageFlag
def vaultClient
def vaultAppRoleToken
def utils

pipeline {

    agent {
        label 'k8s-berlin'
    }

    tools {
        go 'go1.15.7'
    }

    options {
        timeout(time: 90, unit: 'MINUTES')
        timestamps()
        buildDiscarder(logRotator(daysToKeepStr: '-1', numToKeepStr: '20', artifactDaysToKeepStr: '-1', artifactNumToKeepStr: '-1'))
    }

    parameters {
        booleanParam(name: 'Build', defaultValue: true, description: '\'true\' triggers image builds')
        booleanParam(name: 'BuildXmake', defaultValue: true, description: '\'true\' triggers image builds via xmake for testing')
        booleanParam(name: 'Release', defaultValue: false, description: '\'true\' publishes the git tag and the docker image')
        string(name: 'TREEISH', defaultValue: 'main', description: 'the git branch name to deploy from')
        string(name: 'BuildContext', defaultValue: '', description: 'context to patch versions')
        string(name: 'ComponentName', defaultValue: '', description: 'same as the image folder name')
        booleanParam(name: 'RunUnitTests', defaultValue: true, description: '\'true\' runs unit tests')
        booleanParam(name: 'RunStaticScans', defaultValue: true, description: '\'true\' runs linters')
        booleanParam(name: 'RunWhitesource', defaultValue: true, description: '\'true\' triggers Whitesource scan for docker image, any other value will not')
        booleanParam(name: 'RunPPMSComplianceForImage', defaultValue: true, description: '\'true\' triggers Whitesource scan for docker image, any other value will not')
        booleanParam(name: 'RunProtecode', defaultValue: true, description: '\'true\' triggers Protecode scan, any other value will not')
    }

    environment {
        AUDITLOG_VALUES=""
        KUBECONFIG="/var/lib/jenkins/.kube/kube_gardenerAws_eu-west-1_aicore-pr-valid_config"
        SERVICE_PATH="."
        HELM_PATH="helm"
        CHART_NAME="nvidia-installer"
        SAP_ARTIFACTORY_DMZ_API_TOKEN_CREDENTIAL_ID="sap-artifactory-dmz-api-token"
        SAP_REMOTE_CACHE_REGISTRY="remote-docker.docker.repositories.sapcdn.io"
        VAULT_APPROLE_CRED_ID="jenkins-ai-foundation-user-privileged"
        XMAKE_REGISTRY="public.int.repositories.cloud.sap"
        API_TOKEN_FOR_DASHBOARD="JENKINS_API_TOKEN"
    }

    stages {
        stage('Initialize') {
            steps {
                script {
                    echo "Patching versions"
                    sh "mono/scripts/run_mono_update.sh ${params.BuildContext}"
                    sh "mono/scripts/run_mono_export_context.sh ${params.BuildContext} ${env.SERVICE_PATH}"

                    context = readYaml file: 'env.yaml'
                    env.VERSION=context["builtin"]["version"]
                    env.GARDENLINUX_VERSION=""
                    env.DRIVER_VERSION=""
                    env.PRERELEASE_VERSION = ""
                    env.IMAGE_SUFFIX=context["image_suffix"]
                    env.DOCKER_REGISTRY=context["docker_registry"]
                    env.BRANCH_NAME=context["branch_name"]

                    xmake = load("scripts/xmake_utils.groovy")
                    git = load("scripts/git_utils.groovy")
                    utils = load("scripts/general_utils.groovy")
                    xmake.set_build_config("nvidia-installer") // Load one xmake config, which we will replicate & edit
                    def base_build = xmake.build_config[0]
                    // Iterate through garden linux & driver versions to create an xmake build config for each
                    def nvidiaDriverVersions = readYaml text: context["nvidiaDriverVersion"]
                    def gardenLinuxMap = readYaml text: context["gardenLinux"]
                    def gardenLinuxVersions = gardenLinuxMap.collect{entry -> entry.value}
                    def builds = []
                    gardenLinuxVersions.each {
                        def gardenLinux = it
                        nvidiaDriverVersions.each {
                            def nvidiaDriverVersion = it
                            def name = base_build['name'] + "-${gardenLinux.version}-${nvidiaDriverVersion}"
                            def entry = [
                                name: name,
                                jobname: base_build['jobname'],
                                gid: context["gid"],
                                aid: name,
                                uri: context["gid"] + "/" + name,
                                dockerfile_path: base_build['dockerfile_path'],
                                docker_build_args: [
                                    DRIVER_VERSION: nvidiaDriverVersion,
                                    GARDENLINUX_VERSION: gardenLinux.version,
                                    DEBIAN_BASE_IMAGE_TAG: gardenLinux.debianBaseImageTag
                                ]
                            ]
                            builds.add(entry)
                        }
                    }
                    // Replace the template build from config/service with our new list of builds
                    xmake.build_config = builds

                    assert env.GIT_COMMIT == git.get_commit():\
                    "Jenkins GIT_COMMIT \"${namenv.GIT_COMMIT}\" must match \
                    the actual branch commit \"${git.get_commit()}\". \
                    If this is not the case Jenkins is probably doing a merge before it builds."

                    assert env.version.contains(env.GARDENLINUX_VERSION)
                    assert env.version.contains(env.DRIVER_VERSION)

                    withCredentials([usernamePassword(credentialsId: 'aicore_gcr_dev', passwordVariable: 'DOCKER_PASS', usernameVariable: 'DOCKER_USER')]) {
                        sh 'echo "${DOCKER_PASS}" | docker login -u ${DOCKER_USER} --password-stdin eu.gcr.io'
                    }
                }
            }
        }

        stage('Lint') {
            when { expression { params.RunStaticScans == true } }
            steps {
                sh "rm -rf helm-lint.out"
                sh "rm -rf shellcheck.out"
                sh "mono/scripts/run_mono.sh run ${env.SERVICE_PATH}:lint -e ${params.BuildContext}"
            }
            post {
                always {
                    archiveArtifacts artifacts: "helm-lint.out", fingerprint: true
                    archiveArtifacts artifacts: "shellcheck.out", fingerprint: true
                }
            }
        }

        stage('Unit Test') {
            when { expression { params.RunUnitTests == true } }
            steps {
                sh "rm -rf nvidia-installer.yaml"
                sh "rm -rf kubeconform.out"
                sh "mono/scripts/run_mono.sh run ${env.SERVICE_PATH}:unit -e ${params.BuildContext}"
            }
            post {
                always {
                    archiveArtifacts artifacts: "nvidia-installer.yaml", fingerprint: true
                    archiveArtifacts artifacts: "kubeconform.out", fingerprint: true
                }
            }
        }

        stage('Piper Setup') {
            //Setting up for upcoming piper steps (SapCumulusUpload, )
            // Update the configs in '.pipeline/config.yml'
            steps {
                script{
                    dir("${WORKSPACE}"){
                        setupPipelineEnvironment script: this
                        //Setting up params for ws scan for docker images
                        if(params.RunWhitesource == true){
                            wsDockerScanConfig = globalPipelineEnvironment.configuration.steps?.whitesourceExecuteScan?.custom_wsDockerScanConfig ?: null
                            wsDockerProductToken = globalPipelineEnvironment.configuration.steps?.whitesourceExecuteScan?.custom_CTNR_Product_Token ?: null
                            wsScanIncludingBaseImageFlag = globalPipelineEnvironment.configuration.steps?.whitesourceExecuteScan?.custom_wsDockerScanWithBaseImage ?: false
                            def doesWSDockerConfigExist = fileExists "${wsDockerScanConfig}"
                            def checkIfProductNameAndConfigFileExist = {
                                (wsDockerProductToken == null) ? {
                                    throw new Exception("'custom_CTNR_Product_Token' not defined for whitesource container scan");
                                }() : doesWSDockerConfigExist ? true: {
                                    throw new Exception("'custom_wsDockerScanConfig' not defined for whitesource container scan");
                                }();
                            }
                            //Calling closure to check if there has been any misconfiguration in ws docker scan params
                            checkIfProductNameAndConfigFileExist.call()
                        }

                        def vaultAddress = 'https://vault.ml.only.sap'
                        if (params.RunSonarQube == true || params.RunWhitesource == true ) {
                            withCredentials([usernamePassword(credentialsId: 'jenkins-ai-foundation-user-privileged', passwordVariable: 'SECRET_ID', usernameVariable: 'APPROLE_ID')]) {
                                vaultClient = new aif.VaultClient(this, vaultAddress)
                                vaultAppRoleToken = vaultClient.getVaultAppRoleToken(APPROLE_ID, SECRET_ID)
                            }
                        }
                    }
                }
            }
        }

        stage('Build images') {
            parallel {
                stage("Build docker image") {
                    when { expression { params.Build == true } }
                    steps {
                        sh "mono/scripts/run_mono.sh run ${env.SERVICE_PATH}:build -e ${params.BuildContext}"
                    }
                }
            }
        }

        stage('Setup Git Remote') {
            when { expression { params.Release == true } }
            steps {
                sh "git remote set-url origin git@github.wdf.sap.corp:ICN-ML/aicore.git"
            }
        }

        stage('Tag Release') {
            when { expression { params.Release == true } }
            steps {
                sh "git tag -a rel/${env.SERVICE_PATH}/${VERSION} -m 'creating release tag for ${env.SERVICE_PATH}/${VERSION}'"
                sh "git push --tags"
            }
        }


        stage('Protecode Scan') {
            when { expression { params.RunProtecode == true } }
            steps {
                script {
                    dir("${WORKSPACE}"){
                        // Scan only the first config, as all are using the same base image and just copy in the
                        // compiled kernel modules
                        utils.retry(){
                            def config = xmake.build_config[0]
                            if(config.uri != "") {
                                def imageURI = "${DOCKER_REGISTRY}${config.uri}${IMAGE_SUFFIX}:${VERSION}"
                                def version = env.BRANCH_NAME == 'main'? env.BRANCH_NAME : "${VERSION}"
                                utils.runProtecodeScan("nvidia-installer", version, imageURI, params.Release)

                            }
                        }
                    }
                }
            }
        }

        stage('WhiteSource') {
            when { expression { params.RunWhitesource == true } }
            steps {
                script{
                    def vaultAddress = 'https://vault.ml.only.sap'
                    def version = env.BRANCH_NAME == 'main'? env.BRANCH_NAME : "${VERSION}"
                    dir("${WORKSPACE}"){
                        // Scan only the first config, as all are using the same base image and just copy in the
                        // compiled kernel modules
                        def config = xmake.build_config[0]
                        utils.retry(){
                            if(config.uri != "") {
                                def imageURI = "${DOCKER_REGISTRY}${config.uri}${IMAGE_SUFFIX}:${VERSION}"
                                sh "docker pull ${imageURI}"
                                wsDockerGeneratedProjectName = "${config.name} ${version}"
                                new aif.WhitesourceScan(this).execute("${config.name}","${version}", "${wsDockerScanConfig}", env.SAP_REMOTE_CACHE_REGISTRY, env.SAP_ARTIFACTORY_DMZ_API_TOKEN_CREDENTIAL_ID, false,false, null,null,aif.WhiteSourceScanConstants.Mode.CONTAINER_SCAN, imageURI,env.VAULT_APPROLE_CRED_ID, vaultAddress)
                                println("The generated ws Project name is ${wsDockerGeneratedProjectName}")
                            }
                        }
                    }
                }
            }
        }

        stage('PPMS Compliance Docker Scan'){
            when {
                allOf {
                    expression { params.RunWhitesource == true }
                    expression { params.RunPPMSComplianceForImage == true }
                }
            }
            steps{
                script {
                    // Scan only the first config, as all are using the same base image and just copy in the
                    // compiled kernel modules
                    def config = xmake.build_config[0]
                    utils.retry(){
                        if(config.uri != "") {
                            println("Will run PPMS scan in this case for project ${wsDockerGeneratedProjectName}")
                            new aif.WhitesourceScan(this).execute("${config.name}", "${VERSION}", null, env.SAP_REMOTE_CACHE_REGISTRY, env.SAP_ARTIFACTORY_DMZ_API_TOKEN_CREDENTIAL_ID, true, true, wsDockerProductToken,  wsDockerGeneratedProjectName)
                        }
                    }
                }
            }
        }

    }
     post{
        always {
            script {
                utils.send_job_to_devops_dashboard(env, this)
            }
        }
    }
}