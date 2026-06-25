-- CreateTable
CREATE TABLE "Parcel" (
    "id" TEXT NOT NULL,
    "tracking_code" TEXT NOT NULL,
    "sender" TEXT NOT NULL,
    "recipient_email" TEXT NOT NULL,
    "destination_lat" DOUBLE PRECISION NOT NULL,
    "destination_lng" DOUBLE PRECISION NOT NULL,
    "status" TEXT NOT NULL DEFAULT 'CREATED',
    "created_at" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "Parcel_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "ParcelEvent" (
    "id" TEXT NOT NULL,
    "parcel_id" TEXT NOT NULL,
    "status" TEXT NOT NULL,
    "message" TEXT NOT NULL,
    "timestamp" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "ParcelEvent_pkey" PRIMARY KEY ("id")
);

-- CreateIndex
CREATE UNIQUE INDEX "Parcel_tracking_code_key" ON "Parcel"("tracking_code");

-- AddForeignKey
ALTER TABLE "ParcelEvent" ADD CONSTRAINT "ParcelEvent_parcel_id_fkey" FOREIGN KEY ("parcel_id") REFERENCES "Parcel"("id") ON DELETE RESTRICT ON UPDATE CASCADE;
