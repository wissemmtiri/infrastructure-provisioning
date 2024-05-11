pipeline {
    agent any
    stages {
        stage('Lint'){
            steps {
                bash 'terraform fmt'
            }
        }

        //stage('Security Check'){
        //   steps{
        //        sh 'snyk iac test .'
        //    }
        //}

        stage('Validation'){
            steps {
                bash 'terraform init'
                bash 'terraform validate'
            }
        }

        stage('Plan'){
            steps {
                bash '''
                source /.connection.env
                terraform plan -out=plan.tfplan
                '''
            }
        }

        stage('Move Plan'){
            steps {
                bash 'mkdir -p /home/wsl/pfa/CD/terraform-files'
                bash 'mv plan.tfplan /home/wsl/pfa/CD/terraform-files'
            }
        }
    }

    post {
        always {
            echo 'Cleaning up...'
            bash 'rm -rf *.tf'
        }

        success {
            echo 'All checks passed!'
        }

        failure {
            echo 'Notifying the team...'
        }
    }
}
