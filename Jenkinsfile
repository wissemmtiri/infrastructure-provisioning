pipeline {
    agent any
    stages {
        stage('Lint'){
            steps {
                sh 'terraform fmt'
            }
        }

        //stage('Security Check'){
        //   steps{
        //        sh 'snyk iac test .'
        //    }
        //}

        stage('Validation'){
            steps {
                sh 'terraform init'
                sh 'terraform validate'
            }
        }

        stage('Plan'){
            steps {
                sh 'terraform plan -out=plan.tfplan'
            }
        }

        stage('Move Plan'){
            steps {
                sh 'mkdir -p /home/wsl/pfa/CD/terraform-files'
                sh 'mv plan.tfplan /home/wsl/pfa/CD/terraform-files'
            }
        }
    }

    post {
        always {
            echo 'Cleaning up...'
            sh 'rm -rf *.tf'
        }

        success {
            echo 'All checks passed!'
        }

        failure {
            echo 'Notifying the team...'
        }
    }
}
