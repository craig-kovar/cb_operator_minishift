CREATE DATABASE  IF NOT EXISTS `cb_demo` /*!40100 DEFAULT CHARACTER SET utf8 */;
USE `cb_demo`;
-- MySQL dump 10.13  Distrib 5.7.17, for macos10.12 (x86_64)
--
-- Host: 127.0.0.1    Database: cb_demo
-- ------------------------------------------------------
-- Server version	5.7.22

/*!40101 SET @OLD_CHARACTER_SET_CLIENT=@@CHARACTER_SET_CLIENT */;
/*!40101 SET @OLD_CHARACTER_SET_RESULTS=@@CHARACTER_SET_RESULTS */;
/*!40101 SET @OLD_COLLATION_CONNECTION=@@COLLATION_CONNECTION */;
/*!40101 SET NAMES utf8 */;
/*!40103 SET @OLD_TIME_ZONE=@@TIME_ZONE */;
/*!40103 SET TIME_ZONE='+00:00' */;
/*!40014 SET @OLD_UNIQUE_CHECKS=@@UNIQUE_CHECKS, UNIQUE_CHECKS=0 */;
/*!40014 SET @OLD_FOREIGN_KEY_CHECKS=@@FOREIGN_KEY_CHECKS, FOREIGN_KEY_CHECKS=0 */;
/*!40101 SET @OLD_SQL_MODE=@@SQL_MODE, SQL_MODE='NO_AUTO_VALUE_ON_ZERO' */;
/*!40111 SET @OLD_SQL_NOTES=@@SQL_NOTES, SQL_NOTES=0 */;

--
-- Table structure for table `customer_product_details`
--

DROP TABLE IF EXISTS `customer_product_details`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!40101 SET character_set_client = utf8 */;
CREATE TABLE `customer_product_details` (
  `id` varchar(255) NOT NULL,
  `customer_email` varchar(255) DEFAULT NULL,
  PRIMARY KEY (`id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Dumping data for table `customer_product_details`
--

LOCK TABLES `customer_product_details` WRITE;
/*!40000 ALTER TABLE `customer_product_details` DISABLE KEYS */;
INSERT INTO `customer_product_details` VALUES ('1','balaji@cb.com'),('2','john@cb.com'),('3','peter@cb.com'),('4','mark@cb.com'),('5','richard@cb.com');
/*!40000 ALTER TABLE `customer_product_details` ENABLE KEYS */;
UNLOCK TABLES;

--
-- Table structure for table `orders`
--

DROP TABLE IF EXISTS `orders`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!40101 SET character_set_client = utf8 */;
CREATE TABLE `orders` (
  `order_id` varchar(255) NOT NULL,
  `purchase_date` datetime DEFAULT NULL,
  `expiration_date` datetime DEFAULT NULL,
  `quantity` int(11) NOT NULL DEFAULT '0',
  `customer_product_id_fk` varchar(255) NOT NULL,
  `product_id_fk` varchar(255) NOT NULL,
  PRIMARY KEY (`order_id`),
  KEY `FK8cvh33kp0afuonbdmsb51phys` (`customer_product_id_fk`),
  KEY `FKgd3ps6gmddy3ycgj4v1wuifv4` (`product_id_fk`),
  CONSTRAINT `FK8cvh33kp0afuonbdmsb51phys` FOREIGN KEY (`customer_product_id_fk`) REFERENCES `customer_product_details` (`id`),
  CONSTRAINT `FKgd3ps6gmddy3ycgj4v1wuifv4` FOREIGN KEY (`product_id_fk`) REFERENCES `product` (`product_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Dumping data for table `orders`
--

LOCK TABLES `orders` WRITE;
/*!40000 ALTER TABLE `orders` DISABLE KEYS */;
INSERT INTO `orders` VALUES ('1','2017-12-01 00:00:00','2018-12-01 00:00:00',1,'1','2'),('2','2017-09-15 00:00:00','2018-08-15 00:00:00',1,'1','3'),('3','2017-10-12 00:00:00','2018-09-10 00:00:00',1,'2','1'),('4','2017-10-12 00:00:00','2018-09-10 00:00:00',1,'2','5');
/*!40000 ALTER TABLE `orders` ENABLE KEYS */;
UNLOCK TABLES;

--
-- Table structure for table `product`
--

DROP TABLE IF EXISTS `product`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!40101 SET character_set_client = utf8 */;
CREATE TABLE `product` (
  `product_id` varchar(255) NOT NULL,
  `name` varchar(255) DEFAULT NULL,
  `description` varchar(255) DEFAULT NULL,
  `category` varchar(255) DEFAULT NULL,
  PRIMARY KEY (`product_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Dumping data for table `product`
--

LOCK TABLES `product` WRITE;
/*!40000 ALTER TABLE `product` DISABLE KEYS */;
INSERT INTO `product` VALUES ('1','Cloud','Coud-native data platform','Couchbase Server'),('2','N1QL','High-performance query engine','Couchbase Server'),('3','Eventing','Real-time server-side event processing','Couchbase Server'),('4','Full-Text Search','Real-time search','Couchbase Server'),('5','CB Lite','Offline-first experiences','Couchbase Mobile'),('6','Sync Gateway','Automatic sync','Couchbase Mobile');
/*!40000 ALTER TABLE `product` ENABLE KEYS */;
UNLOCK TABLES;

--
-- Dumping events for database 'cb_demo'
--

--
-- Dumping routines for database 'cb_demo'
--
/*!40103 SET TIME_ZONE=@OLD_TIME_ZONE */;

/*!40101 SET SQL_MODE=@OLD_SQL_MODE */;
/*!40014 SET FOREIGN_KEY_CHECKS=@OLD_FOREIGN_KEY_CHECKS */;
/*!40014 SET UNIQUE_CHECKS=@OLD_UNIQUE_CHECKS */;
/*!40101 SET CHARACTER_SET_CLIENT=@OLD_CHARACTER_SET_CLIENT */;
/*!40101 SET CHARACTER_SET_RESULTS=@OLD_CHARACTER_SET_RESULTS */;
/*!40101 SET COLLATION_CONNECTION=@OLD_COLLATION_CONNECTION */;
/*!40111 SET SQL_NOTES=@OLD_SQL_NOTES */;

-- Dump completed on 2018-10-18 14:35:08
