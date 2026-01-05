/*
  RadiaCode Basic Example
  
  This example demonstrates how to connect to a RadiaCode device over Bluetooth
  and read basic radiation data.
*/

#include <RadiaCode.h>

// Bluetooth MAC address
const char* bluetoothMac = "52:43:06:70:24:67"; // Replace with your device's MAC address

// Create RadiaCode instance
RadiaCode* radiacode = nullptr;

// Variables for storing measurements
float countRate = 0;
float doseRate = 0;
float temperature = 0;
float batteryLevel = 0;
String serialNum = "";

void setup(void)
{
    // Initialize serial
    Serial.begin(115200);
    while (!Serial && millis() < 5000);

    Serial.println("RadiaCode Basic Example");
    Serial.println("------------------------");

    // Connect to RadiaCode device with error handling
    try
    {
        Serial.println("Connecting via Bluetooth...");
        radiacode = new RadiaCode(bluetoothMac);

        if (radiacode != nullptr)
        {
            // Test basic connection
            serialNum = radiacode->serialNumber();
            if (serialNum.length() > 0)
            {
                Serial.print("Connected to RadiaCode device: ");
                Serial.println(serialNum);

                // Get firmware version
                auto version = radiacode->fwVersion();
                int target_major = std::get<3>(version);
                int target_minor = std::get<4>(version);
                String target_date = std::get<5>(version);

                Serial.print("Firmware version: ");
                Serial.print(target_major);
                Serial.print(".");
                Serial.print(target_minor);
                Serial.print(" (");
                Serial.print(target_date);
                Serial.println(")");

                // Get energy calibration coefficients
                std::vector<float> calib = radiacode->energyCalib();
                if (calib.size() >= 3)
                {
                    Serial.printf("Energy calibration coefficients: a0= %f, a1= %f, a2= %f\n", calib[0], calib[1], calib[2]);
                }

                Serial.println("------------------------");
            }
            else
            {
                Serial.println("Failed to get device serial number - connection failed!");
                delete radiacode;
                radiacode = nullptr;
            }
        }
        else
        {
            Serial.println("Failed to create RadiaCode instance!");
        }
    }
    catch (...)
    {
        Serial.println("Exception during RadiaCode initialization!");
        if (radiacode != nullptr)
        {
            delete radiacode;
            radiacode = nullptr;
        }
    }
}

void loop(void) 
{
    if (radiacode == nullptr)
    {
        Serial.println("No device connected.");
        delay(5000);
        return;
    }

    // Add error handling
    try
    {
        // Read data buffer to get current measurements
        std::vector<DataItem*> data = radiacode->dataBuf();

        // Process data safely
        int realTimeCount = 0, rareDataCount = 0, rawDataCount = 0, otherCount = 0;
        for (size_t i = 0; i < data.size(); i++)
        {
            DataItem* item = data[i];
            if (item == nullptr) continue;

            // Check for real-time data
            if (item->type == TYPE_REAL_TIME_DATA)
            {
                RealTimeData* rtData = (RealTimeData*)item;
                if (rtData != nullptr)
                {
                    countRate = rtData->count_rate;
                    doseRate = rtData->dose_rate;
                    realTimeCount++;
                }
            }

            // Check for raw data (might contain dose rate from gid=9)
            else if (item->type == TYPE_RAW_DATA)
            {
                RawData* rawData = (RawData*)item;
                if (rawData != nullptr)
                {
                    // Use dose rate from raw data if real-time data doesn't have it
                    if (doseRate == 0.0f && rawData->dose_rate > 0.0f)
                    {
                        doseRate = rawData->dose_rate;
                    }
                    rawDataCount++;
                }
            }

            // Check for rare data (temperature and battery)
            else if (item->type == TYPE_RARE_DATA)
            {
                RareData* rareData = (RareData*)item;
                if (rareData != nullptr)
                {
                    temperature = rareData->temperature;
                    batteryLevel = rareData->charge_level;
                    rareDataCount++;
                }
            }
            else
            {
                otherCount++;
            }
        }

        // Clean up data objects safely
        for (size_t i = 0; i < data.size(); i++)
        {
            if (data[i] != nullptr)
            {
                delete data[i];
                data[i] = nullptr;
            }
        }
        data.clear();

        // Display current measurements
        Serial.print("Count rate: ");
        Serial.print(countRate);
        Serial.println(" CPS");

        Serial.print("Dose rate: ");
        Serial.print(doseRate * 10000.0f);
        Serial.println(" µSv/h");

        Serial.print("Temperature: ");
        Serial.print(temperature);
        Serial.println(" °C");

        Serial.print("Battery level: ");
        Serial.print(batteryLevel);
        Serial.println("%");

        Serial.println("------------------------");

    }
    catch (...)
    {
        Serial.println("Error reading data from device - restarting...");
        delay(1000);
        ESP.restart();
    }

    // Wait before next reading
    delay(2000);
}