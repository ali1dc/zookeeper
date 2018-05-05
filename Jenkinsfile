pipeline {
  agent any
  stages {
    stage('Commit') {
      steps {
        sh 'which bundle || gem install bundler'
        sh 'bundle install'
        sh 'rubocop'
        sh '''
          # create vendor cookbooks
          berks vendor cookbooks/vendor-cookbooks
        '''
        sh '''
          # Build AMI with Packer
          # packer build packer.json
          ami_id="$(cat manifest.json | jq -r .builds[0].artifact_id | cut -d\':\' -f2)"
          # ami_id='ami-7390160c'
          keystore.rb store --table $inventory_store --kmsid $kms_id --keyname "ZOOKEEPER_LATEST_AMI" --value ${ami_id}
        '''
      }
    }
    stage('Deployment') {
      steps {
        sh '''
          echo "start deployment"
          ami_id="$(keystore.rb retrieve --table $inventory_store --keyname ZOOKEEPER_LATEST_AMI)"
          echo "deploy this ami: ${ami_id}"
        '''
      }
    }
  }
}
