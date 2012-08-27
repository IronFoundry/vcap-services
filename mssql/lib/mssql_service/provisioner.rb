require 'mssql_service/common'

class VCAP::Services::MSSQL::Provisioner < VCAP::Services::Base::Provisioner
  include VCAP::Services::MSSQL::Common

  # TODO
  # def create_snapshot_job
  #   VCAP::Services::MSSQL::Snapshot::CreateSnapshotJob
  # end

  # def rollback_snapshot_job
  #   VCAP::Services::MSSQL::Snapshot::RollbackSnapshotJob
  # end

  # def delete_snapshot_job
  #   VCAP::Services::Base::AsyncJob::Snapshot::BaseDeleteSnapshotJob
  # end

  # def create_serialized_url_job
  #   VCAP::Services::Base::AsyncJob::Serialization::BaseCreateSerializedURLJob
  # end

  # def import_from_url_job
  #   VCAP::Services::MSSQL::Serialization::ImportFromURLJob
  # end

end
